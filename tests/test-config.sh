#!/usr/bin/env bash
set -Eeuo pipefail
test_case="configuration test setup"
trap 'echo "FAIL: $test_case (${BASH_SOURCE[0]}:$LINENO)" >&2' ERR
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

test_case="maintained helper and resolved snapshot are valid"
# Validate the maintained helper and the current resolved snapshot independently.
jq --arg mode helper -f "$repo/scripts/validate-config.jq" "$repo/versions-helper.json" >/dev/null
jq --arg fixture current \
    -f "$repo/tests/fixtures.jq" "${TEST_VERSIONS_FILE:-$repo/versions.json}" \
    | jq --arg mode resolved -f "$repo/scripts/validate-config.jq" >/dev/null

# Malformed input cases use one isolated fake series, never a maintained release.
jq --arg fixture synthetic \
    -f "$repo/tests/fixtures.jq" "${TEST_VERSIONS_FILE:-$repo/versions.json}" \
    | jq '.["100.0"]' > "$work/settings.json"
check() {
    jq '{"100.0": .}' "$1" | jq --arg mode "${2:-resolved}" -f "$repo/scripts/validate-config.jq" >/dev/null
}
# Humans provide settings and versions, including custom package URLs. Hashes
# are generated into the resolved snapshot and must never be required here.
jq 'walk(if type == "object" then del(.sha256, .sha512) else . end)' \
    "$work/settings.json" > "$work/helper.json"
test_case="helper accepts versions and settings without checksums"
check "$work/helper.json" helper
if check "$work/settings.json" helper >"$work/log" 2>&1; then
    echo 'FAIL: helper accepted generated checksums' >&2; exit 1
fi
reject() {
    test_case="reject invalid configuration: $1"
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
reject '.phpVersions[.php].pie["phpredis/phpredis"] = "latest"'
reject '.phpVersions[.php].download.pie.sha256 = "invalid"'
reject '.phpVersions[.php].download.pie.version = "latest"'
reject 'del(.phpVersions[.php].download.pie.package)'
reject '.phpVersions[.php].download.pie.package = "http://example.test/pie.phar"'
reject '.phpVersions[.php].sources["imagick/imagick"].sha256 = "invalid"'
reject '.phpVersions[.php].pecl = .phpVersions[.php].pie'
reject '.phpVersions[.php].apt = ["package;command"]'
reject '.phpVersions[.php].download.pie.destination = "/tmp/../bin/pie"'
reject '.states = {}'
for change in '.states.stable.aliases = []' '.states.stable.aliases = null' 'del(.states.stable.aliases)' 'del(.states.stable)'; do
    test_case="accept optional release setting: $change"
    jq "$change" "$work/settings.json" > "$work/valid.json"
    check "$work/valid.json"
done
echo 'Configuration validation tests passed.'
