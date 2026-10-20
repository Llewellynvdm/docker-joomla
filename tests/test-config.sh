#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
check() { jq --arg mode helper -f scripts/validate-config.jq "$1" >/dev/null; }
check versions-helper.json
reject() {
    jq "$1" versions-helper.json > "$work/config.json"
    if check "$work/config.json" >"$work/log" 2>&1; then
        echo "FAIL: accepted invalid configuration: $1" >&2; exit 1
    fi
}
reject '.["6.2"].states.stable.version = "6.3.0"'
reject '.["6.2"].states.stable.version = "6.2.1-rc1"'
reject '.["6.2"].states.nightly = .["6.2"].states.stable'
reject '.["6.2"].states.stable.aliases = ""'
reject '.["6.2"].states.stable.aliases = false'
reject '.["6.2"].states.stable.aliases = [true]'
reject '.["6.2"].states.stable.aliases = [""]'
reject '.["6.2"].states.stable.package = "https://example.org/package.tar.zst"'
reject '.["6.2"].states.stable.sha512 = "null"'
reject '.["6.2"].php = "8.1"'
reject '.["6.2"].variants = ["apache-dev"]'
reject '.["6.2"].variants = ["apache", "apache"]'
reject '.["6.2"].variant = "missing"'
reject '.["6.2"].variant = ["apache"]'
reject '.["6.2"].packageType = "zip"'
reject '.["6.2"].packageType = false'
reject '.["6.2"].states.stable.packageType = false'
reject '.["6.2"].phpVersions["8.4"].pecl.redis = "latest"'
reject '.["6.2"].development.xdebug.sha256 = "bad"'
reject '.["5.4"].development = .["6.2"].development'
reject '.["6.2"].states = {}'
reject '{"../bad": .["6.2"]}'
for change in '.["6.2"].states.stable.aliases = []' '.["6.2"].states.stable.aliases = null' 'del(.["6.2"].states.stable.aliases)'; do
    jq "$change" versions-helper.json > "$work/config.json"
    check "$work/config.json"
done
jq '.["6.2"].states = {alpha:{version:"6.2.1-alpha1",aliases:[]}, beta:{version:"6.2.1-beta2",aliases:[]}, rc:{version:"6.2.1-rc1",aliases:[]}}' versions-helper.json > "$work/config.json"
check "$work/config.json"
echo 'Configuration validation tests passed.'
