#!/usr/bin/env bash
set -Eeuo pipefail
test_case="manifest test setup"
trap 'echo "FAIL: $test_case (${BASH_SOURCE[0]}:$LINENO)" >&2' ERR
repository="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/repository/scripts" "$temporary/bin"
cp "$repository/generate-stackbrew-library.sh" "$repository/maintainers.json" "$temporary/repository/"
cp "$repository/scripts/"*.jq "$temporary/repository/scripts/"
jq --arg fixture current \
  -f "$repository/tests/fixtures.jq" "${TEST_VERSIONS_FILE:-$repository/versions.json}" >"$temporary/repository/versions.json"

# Stub only architecture discovery; the publication plan uses the active releases.
cat >"$temporary/bin/bashbrew" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$BASHBREW_TEST_LOG"
printf '%s\n' "${BASHBREW_TEST_ARCHITECTURES-amd64 arm64v8}"
MOCK
chmod +x "$temporary/bin/bashbrew"
export PATH="$temporary/bin:$PATH" BASHBREW_TEST_LOG="$temporary/bashbrew.log"
cd "$temporary/repository"
jq -f scripts/tags.jq versions.json >"$temporary/plan.json"
# The 4.4 Bookworm suffix is a fixed compatibility rule in the production
# template, not the selection of a release for this test.
while IFS=$'\t' read -r directory version parent; do
  mkdir -p "$directory"
  printf 'FROM %s\nENV JOOMLA_VERSION=%s\nCOPY runtime.ini /usr/local/etc/php/conf.d/runtime.ini\n' \
    "$parent" "$version" >"$directory/Dockerfile"
  printf '; fixture\n' >"$directory/runtime.ini"
  printf '%s\n' "$parent" >>"$temporary/parents"
done < <(jq -r '.[] | [.directory, .version,
  ("php:" + .php + "-" + .variant + (if .series == "4.4" and .variant != "fpm-alpine" then "-bookworm" else "" end))] | @tsv' "$temporary/plan.json")
mkdir -p obsolete
printf 'FROM unavailable:obsolete\n' >obsolete/Dockerfile
git init -q
git config user.name 'Manifest fixture'
git config user.email 'manifest-fixture@example.test'
git add .
git commit -qm 'Create manifest fixture'

test_case="manifest tags and directories match the publication plan"
./generate-stackbrew-library.sh >"$temporary/manifest"
jq -r '.[] | "Tags: " + (.tags | join(", "))' "$temporary/plan.json" >"$temporary/expected-tags"
grep '^Tags:' "$temporary/manifest" >"$temporary/actual-tags"
cmp "$temporary/expected-tags" "$temporary/actual-tags"
jq -r '.[] | "Directory: " + .directory' "$temporary/plan.json" >"$temporary/expected-paths"
grep '^Directory:' "$temporary/manifest" >"$temporary/actual-paths"
cmp "$temporary/expected-paths" "$temporary/actual-paths"
test_case="discover architectures once per parent image"
[[ "$(wc -l <"$BASHBREW_TEST_LOG")" == "$(sort -u "$temporary/parents" | wc -l)" ]]
grep -q '^Architectures: amd64, arm64v8$' "$temporary/manifest"

test_case="selected track honors repository and ref overrides"
# Select a configured track, regardless of whether it is stable or a prerelease.
selector="$(jq -r '.[0] | .series + "/" + .state' "$temporary/plan.json")"
directory="$(jq -r '.[0].directory' "$temporary/plan.json")"
parent="$(awk '$1 == "FROM" { print $2 }' "$directory/Dockerfile")"
version="$(jq -r '.[0].version' "$temporary/plan.json")"
STACKBREW_GIT_REPO=https://example.test/joomla.git STACKBREW_GIT_FETCH=refs/heads/test \
  ./generate-stackbrew-library.sh "$selector/" >"$temporary/selected"
[[ "$(grep -c '^Directory:' "$temporary/selected")" == "$(jq --arg selector "$selector" '[.[] | select((.series + "/" + .state) == $selector)] | length' "$temporary/plan.json")" ]]
grep -q '^GitRepo: https://example.test/joomla.git$' "$temporary/selected"
grep -q '^GitFetch: refs/heads/test$' "$temporary/selected"

reject() {
  local diagnostic="$1"; shift
  test_case="reject invalid manifest input: $diagnostic"
  if ./generate-stackbrew-library.sh "$@" >"$temporary/output" 2>"$temporary/error"; then
    printf 'FAIL: expected manifest error: %s\n' "$diagnostic" >&2; exit 1
  fi
  if [[ -s "$temporary/output" ]]; then
    echo "FAIL: invalid input produced a partial manifest: $diagnostic" >&2; exit 1
  fi
  if ! grep -Fq "$diagnostic" "$temporary/error"; then
    echo "FAIL: expected diagnostic: $diagnostic; actual error follows" >&2
    cat "$temporary/error" >&2; exit 1
  fi
}
reject 'unknown release selector' unconfigured
mv "$directory/Dockerfile" "$temporary/Dockerfile"
reject "missing $directory/Dockerfile"
mv "$temporary/Dockerfile" "$directory/Dockerfile"
printf '; changed\n' >>"$directory/runtime.ini"
reject 'uncommitted changes'
git add "$directory/runtime.ini"
git commit -qm 'Change a copied runtime file'
test_case="a changed copied file updates the context GitCommit"
./generate-stackbrew-library.sh "$selector" >"$temporary/copied-file"
jq -ne --arg text "$(cat "$temporary/copied-file")" --arg commit "$(git rev-parse HEAD)" --arg directory "$directory" \
  '$text | contains("GitCommit: " + $commit + "\nDirectory: " + $directory)' >/dev/null
for architectures in '' '   ' unrecognised; do
  export BASHBREW_TEST_ARCHITECTURES="$architectures"
  reject 'architecture'
done
unset BASHBREW_TEST_ARCHITECTURES

for instruction in $'COPY \\\n  --from=external:test /tool /tool' \
    $'RUN \\\n  --mount=type=bind,from=external:test,target=/tools true' 'FROM unknown:test'; do
  printf 'FROM %s\nENV JOOMLA_VERSION=%s\n%s\n' "$parent" "$version" "$instruction" >"$directory/Dockerfile"
  git add "$directory/Dockerfile"
  git commit -qm 'Create an unsupported dependency fixture'
  reject 'unsupported image dependencies'
done
printf 'Manifest generation tests passed.\n'
