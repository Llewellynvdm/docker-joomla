#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "FAIL: Dockerfile generation at line $LINENO" >&2' ERR
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp "$repo/build.sh" "$repo/"docker-entrypoint*.sh "$repo/makedb.php" "$repo/maintainers.json" "$work/"
cp -r "$repo/scripts" "$work/"
jq --arg fixture current -f "$repo/tests/fixtures.jq" "${TEST_VERSIONS_FILE:-$repo/versions.json}" >"$work/versions.json"
printf 'must not read helper\n' >"$work/versions-helper.json"
cd "$work"
mkdir retired
printf 'preserve\n' >retired/Dockerfile
./build.sh >/dev/null

contains() {
    if ! grep -Fq -- "$2" "$1"; then
        printf 'Missing %s in %s\n' "$2" "$1" >&2
        return 1
    fi
}
excludes() {
    if grep -Fq -- "$2" "$1"; then
        printf 'Unexpected %s in %s\n' "$2" "$1" >&2
        return 1
    fi
}
count() {
    awk -v token="$2" 'index($0, token) { total++ } END { print total + 0 }' "$1"
}

jq -c -f scripts/tags.jq versions.json | jq -c '.[]' >"$work/contexts"
while IFS= read -r context; do
    directory="$(jq -r '.directory' <<<"$context")"
    dockerfile="$directory/Dockerfile"
    # These expected fields are maps with scalar/array leaves. Object merging
    # selects per-variant overrides after any per-PHP development additions.
    image="$(jq -c --argjson context "$context" '
        .[$context.series].phpVersions[$context.php] as $base
        | (if $context.development then $base.dev else {} end) as $dev
        | $base * $dev * $base.variants[$context.variant]
    ' versions.json)"
    contains "$dockerfile" "FROM $(jq -r '.base' <<<"$image")"
    while IFS= read -r value; do
        contains "$dockerfile" "$value"
    done < <(jq -r '.download[] | .package, .sha256' <<<"$image")
    while IFS= read -r package; do
        contains "$dockerfile" "$package"
    done < <(jq -r '(.pie // {} | to_entries[] | .key + ":" + .value),
                    (.npm // {} | to_entries[] | .key + "@" + .value)' <<<"$image")
    excludes "$dockerfile" '--working-dir=/tmp/extension-'
    excludes "$dockerfile" '--skip-enable-extension'
    excludes "$dockerfile" '/tmp/extension-'
    [[ "$(count "$dockerfile" 'curl --fail')" -eq "$(jq '(.download | length) + 1' <<<"$image")" ]]
    while IFS= read -r value; do
        contains "$dockerfile" "$value"
    done < <(jq -r '.config | to_entries[] | .key, .value[]' <<<"$image")
    [[ "$(count "$dockerfile" 'RUN set -eux;')" == 1 ]]
    while IFS= read -r destination; do
        grep -F 'rm -rf ' "$dockerfile" | grep -Fq -- "$destination"
    done < <(jq -r '.download[] | select(.temporary) | .destination' <<<"$image")
    excludes "$dockerfile" 'COPY zz-'
    if [[ "$(jq -r '.development' <<<"$context")" == false ]]; then
        excludes "$dockerfile" xdebug
        excludes "$dockerfile" nodejs
    fi
    # Parse every complete generated RUN instruction with the target shell.
    while IFS= read -r line; do
        if [[ "$line" == 'RUN '* ]]; then
            sh -n <<<"${line#RUN }"
        fi
    done < <(sed ':join; /\\$/ { N; s/\\\n//; b join; }' "$dockerfile")
done <"$work/contexts"
printf 'preserve\n' | cmp - retired/Dockerfile

# Exercise selections absent from the maintained matrix without assuming versions.
IFS=$'\t' read -r series state php variant < <(jq -r '
    to_entries[0] | [.key, (.value.states | keys[0]),
                    (.value.phpVersions | keys[0]), .value.variants[0]] | @tsv
' versions.json)
literal="custom.value=can't \$(touch $work/executed)"
configure_literal="--with-example=can't \"quoted\" \$(touch $work/executed-configure) \`touch $work/executed-backtick\`/\${DEB_BUILD_MULTIARCH}/tail"
jq --arg series "$series" --arg php "$php" --arg variant "$variant" \
    --arg path "$work/quoted.ini" --arg value "$literal" --arg configure "$configure_literal" '
    .[$series].phpVersions[$php].dev.apt = ["sentinel-dev-package"]
    | .[$series].phpVersions[$php].dev.apk = ["sentinel-dev-package"]
    | .[$series].phpVersions[$php].dev.config = {"/tmp/custom.ini": ["custom.value=${RUNTIME_VALUE}"]}
    | .[$series].phpVersions[$php].dev.config[$path] = [$value]
    | .[$series].phpVersions[$php].extensions.configure.example = [$configure]
    | .[$series].phpVersions[$php].variants[$variant].base = "php:100.0-test"
' versions.json >"$work/trial.json"
# Source the generator without invoking its publication entry point.
# shellcheck source=/dev/null
source ./build.sh
render() {
    render_dockerfile "$1" "$series" "$state" "$2" "$variant" "$3" >"$4"
}
render "$work/trial.json" "$php" 0 "$work/normal"
render "$work/trial.json" "$php" 1 "$work/dev"
excludes "$work/normal" sentinel-dev-package
contains "$work/dev" sentinel-dev-package
contains "$work/dev" /tmp/custom.ini
# The renderer must retain the target container's runtime variable literally.
# shellcheck disable=SC2016
contains "$work/dev" 'custom.value=${RUNTIME_VALUE}'
# Execute only the generated config-file write inside this test's directory.
# Quoting must preserve apostrophes and prevent literal command substitution.
config_step="$(grep -F " > $work/quoted.ini" "$work/dev")"
sh -eu -c "${config_step%$' \\'}"
[[ ! -e "$work/executed" ]]
printf '%s\n' "$literal" | cmp - "$work/quoted.ini"
contains "$work/normal" 'FROM php:100.0-test'
# Only the documented multiarch variable may expand in configure arguments.
# Intercept the helper so no extension is configured or compiled by this test.
mkdir "$work/bin"
cat >"$work/bin/docker-php-ext-configure" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >"$TEST_ARGUMENTS_FILE"
SH
chmod +x "$work/bin/docker-php-ext-configure"
configure_step="$(grep -F 'docker-php-ext-configure example ' "$work/normal")"
DEB_BUILD_MULTIARCH=test-triplet TEST_ARGUMENTS_FILE="$work/configure-arguments" \
    PATH="$work/bin:$PATH" sh -eu -c "${configure_step%$' \\'}"
[[ ! -e "$work/executed-configure" && ! -e "$work/executed-backtick" ]]
# shellcheck disable=SC2016
printf '%s\n' example "${configure_literal//'${DEB_BUILD_MULTIARCH}'/test-triplet}" | cmp - "$work/configure-arguments"
jq --arg series "$series" --arg php "$php" '
    .[$series].phpVersions["100.0"] = (.[$series].phpVersions[$php] | del(.dev))
' "$work/trial.json" >"$work/without-dev.json"
render "$work/without-dev.json" 100.0 0 "$work/without-dev"
excludes "$work/without-dev" sentinel-dev-package

# A package without PIE support can use PECL and the PHP image's enable helper.
jq --arg series "$series" --arg php "$php" '
    .[$series].phpVersions[$php].pecl = {example: "100.0.0"}
    | .[$series].phpVersions[$php].extensions.enable += ["example"]
' "$work/trial.json" >"$work/pecl.json"
render "$work/pecl.json" "$php" 0 "$work/pecl"
contains "$work/pecl" 'pecl install '
contains "$work/pecl" example-100.0.0
awk '
    /pecl install / { installed = NR }
    /docker-php-ext-enable / { enabled = NR }
    END { exit !(installed > 0 && enabled > installed) }
' "$work/pecl"
excludes "$work/pecl" /tmp/extension-

find . -name Dockerfile -print0 | sort -z | xargs -0 sha256sum >"$work/before"
./build.sh >/dev/null
find . -name Dockerfile -print0 | sort -z | xargs -0 sha256sum >"$work/after"
cmp "$work/before" "$work/after"
if ./build.sh unknown/state >"$work/log" 2>&1; then echo 'Unknown selector accepted' >&2; exit 1; fi
# Reject invalid resolved input without changing any existing build contexts.
jq --arg series "$series" --arg php "$php" '
    .[$series].phpVersions[$php].download.pie.sha256 = "invalid"
' versions.json >"$work/invalid.json"
mv "$work/invalid.json" versions.json
if ./build.sh >"$work/log" 2>&1; then echo 'Invalid configuration accepted' >&2; exit 1; fi
find . -name Dockerfile -print0 | sort -z | xargs -0 sha256sum >"$work/after"
cmp "$work/before" "$work/after"
echo 'Dockerfile generator tests passed.'
