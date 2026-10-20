#!/usr/bin/env bash
# shellcheck disable=SC2016 # The edit_helper arguments contain jq variables.
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/scripts" "$work/bin"
cp "$root/versions.sh" "$work/repo/"
cp "$root/scripts/validate-config.jq" "$root/scripts/tags.jq" "$work/repo/scripts/"
fixture() {
    jq --slurpfile helper "$root/versions-helper.json" --arg fixture "$1" \
        -f "$root/tests/fixtures.jq" "${TEST_VERSIONS_FILE:-$root/versions.json}"
}
printf 'verified Joomla fixture\n' > "$work/payload"
export FIXTURE_PAYLOAD="$work/payload" FIXTURE_CALLS="$work/calls"
FIXTURE_SHA256="$(sha256sum "$work/payload" | cut -d ' ' -f1)"
FIXTURE_SHA512="$(sha512sum "$work/payload" | cut -d ' ' -f1)"
export FIXTURE_SHA256 FIXTURE_SHA512
: > "$FIXTURE_CALLS"
cat > "$work/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
url= destination=
while (($#)); do
    case "$1" in
        -o) destination="$2"; shift 2 ;;
        -H|--retry|--connect-timeout|--max-time|--proto|--proto-redir) shift 2 ;;
        --*) shift ;;
        https://*) url="$1"; shift ;;
        *) echo "Unexpected curl argument: $1" >&2; exit 1 ;;
    esac
done
printf '%s\n' "$url" >> "$FIXTURE_CALLS"
[[ "${FIXTURE_FAILURE:-}" != http ]] || exit 22
if [[ "$url" == https://api.github.com/* ]]; then
    version="${url##*/}"
    case "$version" in
        *-alpha*) label=Alpha ;; *-beta*) label=Beta ;; *-rc*) label=Release_Candidate ;; *) label=Stable ;;
    esac
    asset="Joomla_${version}-${label}-Full_Package.tar.zst"
    jq -n --arg version "$version" --arg asset "$asset" --arg digest "sha256:$FIXTURE_SHA256" \
       --arg failure "${FIXTURE_FAILURE:-}" '{tag_name:$version, draft:false,
         assets:[{name:$asset,browser_download_url:("https://github.com/joomla/joomla-cms/releases/download/"+$version+"/"+$asset),digest:$digest}]
       } | if $failure == "missing" then .assets=[]
           elif $failure == "duplicate" then .assets += .assets
           elif $failure == "digest" then .assets[0].digest=null else . end' > "$destination"
elif [[ "${FIXTURE_FAILURE:-}" == checksum ]]; then printf 'tampered\n' > "$destination"
else cp "$FIXTURE_PAYLOAD" "$destination"
fi
MOCK
chmod +x "$work/bin/curl"
export PATH="$work/bin:$PATH"
unset VERSIONS_HELPER
cd "$work/repo"

# Every configured release must round-trip through the cache without downloads.
fixture current | jq --arg mode resolved -S -f scripts/validate-config.jq > versions.json
cp versions.json versions-helper.json
cp versions.json "$work/baseline.json"
./versions.sh
cmp versions.json "$work/baseline.json"
[[ ! -s "$FIXTURE_CALLS" ]]
# Changing helper settings must take effect even when package metadata is cached.
jq 'with_entries(.value.phpVersions[.value.php].pecl.redis |= (split(".") | map(tonumber) | .[2] += 1 | map(tostring) | join(".")))' \
    versions-helper.json > .versions-helper.json
./versions.sh
jq -S . .versions-helper.json > "$work/override.json"
cmp versions.json "$work/override.json"
[[ ! -s "$FIXTURE_CALLS" ]]
rm .versions-helper.json versions.json

# Isolated synthetic releases cover states that may not exist in today's matrix.
fixture synthetic | jq 'with_entries(.value.packageType = "tar.zst" | .value.states |= with_entries(.value.packageType = "tar.zst" | del(.value.package, .value.sha512)))' > versions-helper.json
series="$(jq -r 'to_entries[] | select(.value.states.rc != null) | .key' versions-helper.json)"
expected_calls="$(jq '[.[] | .states | length] | add * 2' versions-helper.json)"
./versions.sh
jq -e --arg sha "$FIXTURE_SHA512" 'all(.[] | .states[]; .sha512 == $sha)' versions.json >/dev/null
[[ "$(wc -l < "$FIXTURE_CALLS")" == "$expected_calls" ]]
cp versions.json "$work/baseline.json"
./versions.sh
cmp versions.json "$work/baseline.json"
[[ "$(wc -l < "$FIXTURE_CALLS")" == "$expected_calls" ]]
./versions.sh --force "$series/rc"
[[ "$(wc -l < "$FIXTURE_CALLS")" == "$((expected_calls + 2))" ]]
cmp versions.json "$work/baseline.json"
reject() {
    if "$@" > "$work/log" 2>&1; then echo "FAIL: unexpectedly succeeded: $*" >&2; exit 1; fi
    cmp versions.json "$work/baseline.json"
}
for failure in http missing duplicate digest checksum; do
    reject env FIXTURE_FAILURE="$failure" ./versions.sh --force
done
reject ./versions.sh unknown
edit_helper() { jq --arg series "$series" "$@" versions-helper.json > "$work/helper.json"; mv "$work/helper.json" versions-helper.json; }
edit_helper '.[$series].states.rc.version |= sub("rc1$"; "rc2")'
reject ./versions.sh "$series/stable"
./versions.sh "$series/rc"
jq -e --arg series "$series" --slurpfile helper versions-helper.json \
    '.[$series].states.rc.version == $helper[0][$series].states.rc.version' versions.json >/dev/null

# Removing a track must leave its manually managed files alone.
retired="$(jq -r --arg series "$series" '"\($series)/alpha/php\(.[$series].php)/\(.[$series].variant)"' versions-helper.json)"
mkdir -p "$retired"
printf 'keep\n' > "$retired/manual.txt"
edit_helper 'del(.[$series].states.alpha)'
./versions.sh
jq -e --arg series "$series" '.[$series].states | has("alpha") | not' versions.json >/dev/null
[[ "$(cat "$retired/manual.txt")" == keep ]]

edit_helper --arg sha "$FIXTURE_SHA512" '.[$series].states.stable += {package:"https://example.test/joomla.tar.zst",sha512:$sha}'
./versions.sh "$series/stable"
jq -e --arg series "$series" '.[$series].states.stable.package == "https://example.test/joomla.tar.zst"' versions.json >/dev/null
# Manufacture a legacy cache; this test must not depend on the repository's age.
jq --arg series "$series" '{($series): (.[$series] | .states = {stable: .states.stable})}' versions-helper.json > "$work/helper.json"
mv "$work/helper.json" versions-helper.json
jq --arg series "$series" '{($series): .[$series].states.stable}' versions.json > "$work/legacy.json"
mv "$work/legacy.json" versions.json
before="$(wc -l < "$FIXTURE_CALLS")"
./versions.sh
[[ "$(wc -l < "$FIXTURE_CALLS")" == "$before" ]]
jq --arg mode resolved -f scripts/validate-config.jq versions.json >/dev/null
echo 'Version resolution tests passed.'
