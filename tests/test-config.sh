#!/usr/bin/env bash
set -Eeuo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Validate the maintained helper and the current resolved snapshot independently.
jq --arg mode helper -f "$repo/scripts/validate-config.jq" "$repo/versions-helper.json" >/dev/null
jq --slurpfile helper "$repo/versions-helper.json" --arg fixture current \
    -f "$repo/tests/fixtures.jq" "${TEST_VERSIONS_FILE:-$repo/versions.json}" \
    | jq --arg mode resolved -f "$repo/scripts/validate-config.jq" >/dev/null

# Malformed input cases use one isolated fake series, never a maintained release.
jq --slurpfile helper "$repo/versions-helper.json" --arg fixture synthetic \
    -f "$repo/tests/fixtures.jq" "${TEST_VERSIONS_FILE:-$repo/versions.json}" \
    | jq '.["100.0"]' > "$work/settings.json"
check() {
    jq '{"100.0": .}' "$1" | jq --arg mode helper -f "$repo/scripts/validate-config.jq" >/dev/null
}
reject() {
    jq "$1" "$work/settings.json" > "$work/invalid.json"
    if check "$work/invalid.json" >"$work/log" 2>&1; then
        echo "FAIL: accepted invalid configuration: $1" >&2; exit 1
    fi
}
reject '.states.stable.version = "101.0.0"'
reject '.states.stable.version += "-rc1"'
reject '.states.nightly = .states.stable'
for aliases in '""' 'false' '[true]' '[""]'; do
    reject ".states.stable.aliases = $aliases"
done
reject 'del(.states.stable.sha512)'
reject '.states.stable.sha512 = "invalid"'
reject '.php = "missing"'
reject '.variants = ["apache-dev"]'
reject '.variants += [.variants[0]]'
reject '.variant = "missing"'
reject '.variant = [.variant]'
reject '.packageType = "zip"'
reject '.packageType = false'
reject '.states.stable.packageType = false'
reject '.phpVersions[.php].pecl.redis = "latest"'
reject '.development.xdebug.sha256 = "invalid"'
reject '.states = {}'
for change in '.states.stable.aliases = []' '.states.stable.aliases = null' 'del(.states.stable.aliases)' 'del(.states.stable)'; do
    jq "$change" "$work/settings.json" > "$work/valid.json"
    check "$work/valid.json"
done
echo 'Configuration validation tests passed.'
