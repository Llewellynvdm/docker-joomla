#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."
root="$PWD"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/scripts" "$work/bin"
cp versions.sh "$work/repo/"
cp scripts/validate-config.jq scripts/tags.jq "$work/repo/scripts/"
jq 'with_entries(select(.key == "6.2")) | .["6.2"].states += {
    alpha: {version:"6.2.1-alpha1",aliases:[]},
    beta: {version:"6.2.1-beta1",aliases:["6.2-beta"]},
    rc: {version:"6.2.1-rc1",aliases:["6.2-rc"]}
}' versions-helper.json > "$work/repo/versions-helper.json"
printf 'verified Joomla fixture\n' > "$work/payload"
export FIXTURE_PAYLOAD="$work/payload" FIXTURE_CALLS="$work/calls"
FIXTURE_SHA256="$(sha256sum "$work/payload" | cut -d ' ' -f1)"
FIXTURE_SHA512="$(sha512sum "$work/payload" | cut -d ' ' -f1)"
export FIXTURE_SHA256 FIXTURE_SHA512
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
        *-alpha*) label=Alpha ;;
        *-beta*) label=Beta ;;
        *-rc*) label=Release_Candidate ;;
        *) label=Stable ;;
    esac
    asset="Joomla_${version}-${label}-Full_Package.tar.zst"
    jq -n --arg version "$version" --arg asset "$asset" --arg digest "sha256:$FIXTURE_SHA256" \
       --arg failure "${FIXTURE_FAILURE:-}" '{
         tag_name:$version, draft:false,
         assets:[{name:$asset,browser_download_url:("https://github.com/joomla/joomla-cms/releases/download/"+$version+"/"+$asset),digest:$digest}]
       } | if $failure == "missing" then .assets=[]
           elif $failure == "duplicate" then .assets += .assets
           elif $failure == "digest" then .assets[0].digest=null else . end' > "$destination"
else
    if [[ "${FIXTURE_FAILURE:-}" == checksum ]]; then printf 'tampered\n' > "$destination";
    else cp "$FIXTURE_PAYLOAD" "$destination"; fi
fi
MOCK
chmod +x "$work/bin/curl"
export PATH="$work/bin:$PATH"
cd "$work/repo"
./versions.sh
jq -e --arg sha "$FIXTURE_SHA512" '.["6.2"].states | length == 4 and all(.[]; .sha512 == $sha)' versions.json >/dev/null
[[ "$(wc -l < "$FIXTURE_CALLS")" == 8 ]]
cp versions.json "$work/baseline.json"
./versions.sh
cmp versions.json "$work/baseline.json"
[[ "$(wc -l < "$FIXTURE_CALLS")" == 8 ]]
./versions.sh --force 6.2/rc
[[ "$(wc -l < "$FIXTURE_CALLS")" == 10 ]]
cmp versions.json "$work/baseline.json"

for failure in http missing duplicate digest checksum; do
    if FIXTURE_FAILURE="$failure" ./versions.sh --force > "$work/log" 2>&1; then
        echo "FAIL: accepted $failure response" >&2; exit 1
    fi
    cmp versions.json "$work/baseline.json"
done
if ./versions.sh 6.3 > "$work/log" 2>&1; then echo 'FAIL: accepted unknown selector' >&2; exit 1; fi
cmp versions.json "$work/baseline.json"

# A helper-only release addition does not require an existing directory.
jq '.["6.2"].states.rc.version = "6.2.1-rc2"' versions-helper.json > "$work/helper.json"
cp "$work/helper.json" versions-helper.json
if ./versions.sh 6.2/stable > "$work/log" 2>&1; then echo 'FAIL: silently accepted unselected changed release' >&2; exit 1; fi
cmp versions.json "$work/baseline.json"
./versions.sh 6.2/rc
jq -e '.["6.2"].states.rc.version == "6.2.1-rc2"' versions.json >/dev/null

# Removed releases leave manually managed directories intact.
mkdir -p 6.2/alpha/php8.4/apache
printf 'keep\n' > 6.2/alpha/php8.4/apache/manual.txt
jq 'del(.["6.2"].states.alpha)' versions-helper.json > "$work/helper.json"
cp "$work/helper.json" versions-helper.json
./versions.sh
jq -e '.["6.2"].states | has("alpha") | not' versions.json >/dev/null
[[ "$(cat 6.2/alpha/php8.4/apache/manual.txt)" == keep ]]

# Explicit packages must match the maintainer-provided digest.
jq --arg sha "$FIXTURE_SHA512" '.["6.2"].states.stable += {package:"https://example.org/joomla.tar.zst",sha512:$sha}' versions-helper.json > "$work/helper.json"
cp "$work/helper.json" versions-helper.json
./versions.sh 6.2/stable
jq -e '.["6.2"].states.stable.package == "https://example.org/joomla.tar.zst"' versions.json >/dev/null

# The local override is resolved once, including PECL configuration.
jq '.["6.2"].phpVersions["8.4"].pecl.redis = "6.3.1"' versions-helper.json > .versions-helper.json
./versions.sh
jq -e '.["6.2"].phpVersions["8.4"].pecl.redis == "6.3.1"' versions.json >/dev/null
rm .versions-helper.json

# Old versions.json supplies only cached package data during migration.
cp "$root/versions.json" versions.json
cp "$root/versions-helper.json" versions-helper.json
before="$(wc -l < "$FIXTURE_CALLS")"
./versions.sh
[[ "$(wc -l < "$FIXTURE_CALLS")" == "$before" ]]
jq --arg mode resolved -f scripts/validate-config.jq versions.json >/dev/null
echo 'Version resolution tests passed.'
