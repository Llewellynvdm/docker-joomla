#!/usr/bin/env bash
set -Eeuo pipefail

repository="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/repository/scripts" "$temporary/bin"
cp "$repository/generate-stackbrew-library.sh" "$repository/maintainers.json" "$temporary/repository/"
cp "$repository/scripts/tags.jq" "$repository/scripts/validate-config.jq" "$temporary/repository/scripts/"

# This fixture exercises publication metadata, not downloads or PHP builds.
jq -n '
  {"6.2": {
    php: "8.4",
    phpVersions: {"8.4": {pecl: {imagick: "3.8.1", APCu: "5.1.28", memcached: "3.4.0", redis: "6.3.0"}}},
    variant: "apache",
    variants: ["apache"],
    packageType: "tar.zst",
    development: {
      composer: {version: "2.10.3", sha256: ("a" * 64)},
      xdebug: {version: "3.5.3", sha256: ("b" * 64)}
    },
    states: {
      stable: {version: "6.2.0", aliases: ["6.2", "6", "latest"]},
      rc: {version: "6.2.1-rc1", aliases: ["6.2-rc"]}
    }
  }}
  | .["6.2"].states |= with_entries(.value += {
      package: ("https://example.test/" + .value.version + ".tar.zst"),
      sha512: ("a" * 128)
    })
' >"$temporary/repository/versions.json"

cat >"$temporary/bin/bashbrew" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$BASHBREW_TEST_LOG"
printf '%s\n' "${BASHBREW_TEST_ARCHITECTURES-amd64 arm64v8}"
SH
chmod +x "$temporary/bin/bashbrew"
export PATH="$temporary/bin:$PATH"
export BASHBREW_TEST_LOG="$temporary/bashbrew.log"

cd "$temporary/repository"
jq -c -f scripts/tags.jq versions.json | jq -c '.[]' >"$temporary/plan.json"
while IFS= read -r context; do
  directory="$(jq -r '.directory' <<<"$context")"
  mkdir -p "$directory"
  {
    printf 'FROM php:8.4-apache\n'
    printf 'ENV JOOMLA_VERSION=%s\n' "$(jq -r '.version' <<<"$context")"
    printf 'COPY runtime.ini /usr/local/etc/php/conf.d/runtime.ini\n'
  } >"$directory/Dockerfile"
  printf '; fixture\n' >"$directory/runtime.ini"
done <"$temporary/plan.json"

# Old directories are deliberately retained and must not influence the manifest.
mkdir -p obsolete/php8.4/apache
printf 'FROM unavailable:obsolete\n' >obsolete/php8.4/apache/Dockerfile
git init -q
git config user.name 'Manifest fixture'
git config user.email 'manifest-fixture@example.test'
git add .
git commit -qm 'Create manifest fixture'

./generate-stackbrew-library.sh >"$temporary/manifest"
[[ "$(grep -c '^Directory:' "$temporary/manifest")" == 4 ]]
[[ "$(wc -l <"$BASHBREW_TEST_LOG")" == 1 ]]
if grep -q 'obsolete' "$temporary/manifest"; then
  printf 'FAIL: manifest includes an obsolete directory\n' >&2
  exit 1
fi
grep -q '^Architectures: amd64, arm64v8$' "$temporary/manifest"
grep -Eq '^Tags: .*\bdev\b' "$temporary/manifest"
if grep -q 'latest-dev' "$temporary/manifest"; then
  printf 'FAIL: manifest includes reserved latest-dev alias\n' >&2
  exit 1
fi

STACKBREW_GIT_REPO=https://github.com/Llewellynvdm/docker-joomla.git \
STACKBREW_GIT_FETCH=refs/heads/feature/prerelease-dev-images \
  ./generate-stackbrew-library.sh 6.2/rc >"$temporary/selected"
[[ "$(grep -c '^Directory:' "$temporary/selected")" == 2 ]]
grep -q '^GitRepo: https://github.com/Llewellynvdm/docker-joomla.git$' "$temporary/selected"
grep -q '^GitFetch: refs/heads/feature/prerelease-dev-images$' "$temporary/selected"

reject() {
  local diagnostic="$1"
  shift
  if ./generate-stackbrew-library.sh "$@" >"$temporary/output" 2>"$temporary/error"; then
    printf 'FAIL: expected manifest error: %s\n' "$diagnostic" >&2
    exit 1
  fi
  [[ ! -s "$temporary/output" ]]
  grep -Fq "$diagnostic" "$temporary/error"
}

reject 'unknown release selector' 6.3
mv 6.2/stable/php8.4/apache-dev/Dockerfile "$temporary/Dockerfile"
reject 'missing 6.2/stable/php8.4/apache-dev/Dockerfile'
mv "$temporary/Dockerfile" 6.2/stable/php8.4/apache-dev/Dockerfile

printf '; changed\n' >>6.2/stable/php8.4/apache-dev/runtime.ini
reject 'uncommitted changes'
git add 6.2/stable/php8.4/apache-dev/runtime.ini
git commit -qm 'Change a copied runtime file'
./generate-stackbrew-library.sh 6.2/stable >"$temporary/copied-file"
jq -n --arg text "$(cat "$temporary/copied-file")" --arg commit "$(git rev-parse HEAD)" \
  -e '$text | contains("GitCommit: " + $commit + "\nDirectory: 6.2/stable/php8.4/apache-dev")' >/dev/null

export BASHBREW_TEST_ARCHITECTURES=''
reject 'missing or ambiguous architecture metadata'
export BASHBREW_TEST_ARCHITECTURES='   '
reject 'missing or ambiguous architecture metadata'
export BASHBREW_TEST_ARCHITECTURES='unrecognised'
reject 'unsupported architecture'
unset BASHBREW_TEST_ARCHITECTURES

# Continued instructions must not hide an external image dependency.
for instruction in $'COPY \\\n  --from=composer:2 /usr/bin/composer /usr/bin/composer' \
    $'RUN \\\n  --mount=type=bind,from=composer:2,target=/tools true'; do
  printf 'FROM php:8.4-apache\nENV JOOMLA_VERSION=6.2.0\n%s\n' "$instruction" \
    >6.2/stable/php8.4/apache/Dockerfile
  git add 6.2/stable/php8.4/apache/Dockerfile
  git commit -qm 'Create a continued external dependency fixture'
  reject 'unsupported image dependencies'
done

# A modified parent or second build stage must not inherit guessed architectures.
printf 'FROM unknown:latest\nENV JOOMLA_VERSION=6.2.0\n' >6.2/stable/php8.4/apache/Dockerfile
git add 6.2/stable/php8.4/apache/Dockerfile
git commit -qm 'Create an unsupported dependency fixture'
reject 'unsupported image dependencies'

printf 'Manifest generation tests passed.\n'
