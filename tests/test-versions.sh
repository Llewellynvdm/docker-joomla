#!/usr/bin/env bash
# shellcheck disable=SC2016 # The edit_helper arguments contain jq variables.
set -Eeuo pipefail
test_case="version resolver test setup"
trap 'echo "FAIL: $test_case (${BASH_SOURCE[0]}:$LINENO)" >&2' ERR
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/scripts" "$work/bin"
cp "$root/versions.sh" "$work/repo/"
cp "$root/scripts/validate-config.jq" "$root/scripts/tags.jq" "$work/repo/scripts/"
fixture() {
    jq --arg fixture "$1" \
        -f "$root/tests/fixtures.jq" "${TEST_VERSIONS_FILE:-$root/versions.json}"
}
helper_settings() {
    jq 'walk(if type == "object" then del(.sha256, .sha512) else . end)'
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
        -H|--retry|--retry-max-time|--connect-timeout|--max-time|--proto|--proto-redir) shift 2 ;;
        --*) shift ;;
        https://*) url="$1"; shift ;;
        *) echo "Unexpected curl argument: $1" >&2; exit 1 ;;
    esac
done
printf '%s\n' "$url" >> "$FIXTURE_CALLS"
[[ "${FIXTURE_FAILURE:-}" != http ]] || exit 22
[[ "${FIXTURE_FAILURE:-}" != connection ]] || exit 7
if [[ "${FIXTURE_FAILURE:-}" == pie && "$url" == https://github.com/php/pie/* ]]; then exit 22; fi
if [[ "${FIXTURE_FAILURE:-}" == tool && "$url" != https://*github.com/* ]]; then exit 22; fi
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
           elif $failure == "digest" then .assets[0].digest="invalid"
           elif $failure == "no-digest" then .assets[0].digest=null else . end' > "$destination"
elif [[ "$url" == https://getcomposer.org/*/composer.phar.sha256sum ]]; then
    case "${FIXTURE_FAILURE:-}" in
        composer-digest) printf 'invalid\n' > "$destination" ;;
        composer-checksum) printf '%064d  composer.phar\n' 0 > "$destination" ;;
        *) printf '%s  composer.phar\n' "$FIXTURE_SHA256" > "$destination" ;;
    esac
elif [[ "${FIXTURE_FAILURE:-}" == checksum ]]; then printf 'tampered\n' > "$destination"
else cp "$FIXTURE_PAYLOAD" "$destination"
fi
MOCK
chmod +x "$work/bin/curl"
export PATH="$work/bin:$PATH"
unset VERSIONS_HELPER
cd "$work/repo"

test_case="reuse resolved hashes without downloads"
fixture current | jq --arg mode resolved -S -f scripts/validate-config.jq > versions.json
helper_settings < versions.json > versions-helper.json
cp versions.json "$work/baseline.json"
./versions.sh
cmp versions.json "$work/baseline.json"
[[ ! -s "$FIXTURE_CALLS" ]]

test_case="resolve every configured artifact and reuse URL-keyed checksums"
./versions.sh --force
jq -e --arg sha "$FIXTURE_SHA256" --arg sha512 "$FIXTURE_SHA512" '
  all(.[]; all(.states[]; .sha512 == $sha512))
  and all(.. | objects | select(has("destination")); .sha256 == $sha)
' versions.json >/dev/null
before="$(wc -l < "$FIXTURE_CALLS")"
./versions.sh
[[ "$(wc -l < "$FIXTURE_CALLS")" == "$before" ]]

test_case="settings changes require no downloads"
jq 'map_values(.phpVersions |= map_values(.environment.TEST_SETTING = "configured"))' versions-helper.json > .versions-helper.json
./versions.sh
[[ "$(wc -l < "$FIXTURE_CALLS")" == "$before" ]]
jq -e 'all(.[]; all(.phpVersions[]; .environment.TEST_SETTING == "configured"))' versions.json >/dev/null
mv .versions-helper.json versions-helper.json

test_case="installer version changes do not resolve source downloads"
jq 'walk(if type == "object" then
    (if has("pie") and (.pie | type == "object") and (.pie | has("type") | not) then .pie |= map_values("100.0.0") else . end)
    | (if has("npm") and (.npm | type == "object") then .npm |= map_values("100.0.0") else . end)
  else . end)' versions-helper.json > "$work/helper"
mv "$work/helper" versions-helper.json
./versions.sh
[[ "$(wc -l < "$FIXTURE_CALLS")" == "$before" ]]

test_case="new arbitrary download needs no resolver code"
jq 'to_entries[0].key' versions-helper.json > "$work/series"
series="$(jq -r . "$work/series")"
php="$(jq -r --arg series "$series" '.[$series].php' versions-helper.json)"
jq --arg series "$series" --arg php "$php" '
 .[$series].phpVersions[$php].download.example = {
   version:"100.0.0", package:"https://example.test/tool.phar", type:"binary", destination:"/usr/local/bin/example"}
' versions-helper.json > "$work/helper"
mv "$work/helper" versions-helper.json
./versions.sh
[[ "$(wc -l < "$FIXTURE_CALLS")" == "$((before + 1))" ]]

# A source change, even with the same version, must never reuse an old digest.
test_case="changed URL refreshes its checksum"
jq --arg series "$series" --arg php "$php" '.[$series].phpVersions[$php].download.example.package = "https://example.test/replacement.phar"' versions-helper.json > "$work/helper"
mv "$work/helper" versions-helper.json
./versions.sh
[[ "$(wc -l < "$FIXTURE_CALLS")" == "$((before + 2))" ]]

for failure in http connection missing duplicate digest checksum tool pie composer-digest composer-checksum; do
    test_case="failed $failure resolution leaves existing versions.json untouched"
    cp versions.json "$work/baseline.json"
    if env FIXTURE_FAILURE="$failure" ./versions.sh --force >"$work/error" 2>&1; then
        echo "FAIL: accepted $failure" >&2; exit 1
    fi
    cmp versions.json "$work/baseline.json"
done

test_case="missing published Joomla digest still computes SHA512"
env FIXTURE_FAILURE=no-digest ./versions.sh --force >/dev/null
jq -e --arg sha "$FIXTURE_SHA512" 'all(.[]; all(.states[]; .sha512 == $sha))' versions.json >/dev/null
jq -e '[.. | objects | keys[] | select(. == "sha256" or . == "sha512")] | length == 0' versions-helper.json >/dev/null
if ./versions.sh unknown/state >"$work/error" 2>&1; then echo 'FAIL: unknown selector accepted' >&2; exit 1; fi
echo 'Version resolution tests passed.'
