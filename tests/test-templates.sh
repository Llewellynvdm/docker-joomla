#!/usr/bin/env bash
set -Eeuo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

prepare() {
  mkdir -p "$1/scripts" "$1/development"
  cp "$repo/apply-templates.sh" "$repo/Dockerfile.template" "$repo/"docker-entrypoint*.sh \
    "$repo/makedb.php" "$repo/maintainers.json" "$1/"
  cp "$repo/scripts/validate-config.jq" "$1/scripts/"
  cp "$repo/development/"*.ini "$1/development/"
  if [[ -f "$repo/.jq-template.awk" ]]; then cp "$repo/.jq-template.awk" "$1/"; fi
  # Rendering must use the resolved snapshot, never the helper.
  printf 'the helper must not be read by apply-templates.sh\n' >"$1/versions-helper.json"
}
fail() { echo "FAIL: $*" >&2; exit 1; }
contains() { grep -Fq -- "$2" "$1" || fail "$1 does not contain: $2"; }
excludes() { if grep -Fq -- "$2" "$1"; then fail "$1 unexpectedly contains: $2"; fi; }
snapshot() { find . -type f -print0 | sort -z | xargs -0 sha256sum; }

prepare "$scratch/current"
jq --slurpfile helper "$repo/versions-helper.json" --arg fixture current \
  -f "$repo/tests/fixtures.jq" "${TEST_VERSIONS_FILE:-$repo/versions.json}" >"$scratch/current/versions.json"
cd "$scratch/current"
mkdir retired
printf 'maintainer-owned historical context\n' >retired/Dockerfile
./apply-templates.sh >"$scratch/render.log"
expected="$(jq '[.[] | (.phpVersions | length) * (.variants | length) * (.states | length) * (if .development == null then 1 else 2 end)] | add' versions.json)"
[[ "$(find . -name Dockerfile -type f | wc -l)" -eq "$((expected + 1))" ]] || fail 'context count differs from versions.json'
contains retired/Dockerfile 'maintainer-owned historical context'

check_contexts() {
  # Inspect every configured release/runtime, rather than selecting current releases.
  jq -r '
    to_entries[] | .key as $series | .value as $settings
    | .value.states | to_entries[] | .key as $state | .value as $release
    | $settings.phpVersions | keys[] as $php | $settings.variants[] as $variant
    | (if $settings.development == null then [false] else [false, true] end)[] as $dev
    | [$series, $state, $php, $variant, $dev, $release.version, $release.sha512] | @tsv
  ' versions.json >"$scratch/contexts"
  while IFS=$'\t' read -r series state php variant dev version checksum; do
    directory="$series/$state/php$php/$variant"
    if [[ "$dev" == true ]]; then directory+='-dev'; fi
    dockerfile="$directory/Dockerfile"
    parent="$(awk '$1 == "FROM" { print $2 }' "$dockerfile")"
    expected_parent="php:$php-$variant"
    # Only the fixed legacy 4.4 compatibility rule selects Bookworm.
    if [[ "$series" == 4.4 && "$variant" != fpm-alpine ]]; then expected_parent+='-bookworm'; fi
    [[ "$parent" == "$expected_parent" ]] || fail "incorrect parent: $parent"
    contains "$dockerfile" "ENV JOOMLA_VERSION=$version"
    contains "$dockerfile" "ENV JOOMLA_SHA512=$checksum"
    [[ -x "$directory/docker-entrypoint.sh" ]] || fail 'entrypoint lost executable mode'
    if [[ "$variant" == apache ]]; then
      contains "$dockerfile" 'CMD ["apache2-foreground"]'
    else
      contains "$dockerfile" 'CMD ["php-fpm"]'
      excludes "$dockerfile" 'a2enmod'
    fi
    # PHP integrated OPcache in 8.5; this is a compatibility boundary, not a fixture version.
    if jq -en --arg php "$php" '$php | split(".") | map(tonumber) | . < [8, 5]' >/dev/null; then
      contains "$dockerfile" 'docker-php-ext-enable opcache'
    else
      excludes "$dockerfile" 'docker-php-ext-enable opcache'
    fi
    if [[ "$dev" == true ]]; then
      for tool in composer xdebug npm; do
        for property in version sha256; do
          value="$(jq -r --arg series "$series" --arg tool "$tool" --arg property "$property" '.[$series].development[$tool][$property]' versions.json)"
          contains "$dockerfile" "${tool^^}_${property^^}=$value"
        done
      done
      contains "$dockerfile" 'docker-php-ext-enable --ini-name zz-xdebug.ini xdebug'
      contains "$dockerfile" 'JOOMLA_XDEBUG_CLIENT_HOST=host.docker.internal'
      contains "$dockerfile" 'JOOMLA_XDEBUG_CLIENT_PORT=9003'
      excludes "$dockerfile" 'XDEBUG_CONFIG'
      excludes "$dockerfile" 'EXPOSE 9003'
      cmp development/zz-xdebug-settings.ini "$directory/zz-xdebug-settings.ini"
      cmp development/zz-joomla-development.ini "$directory/zz-joomla-development.ini"
    else
      excludes "$dockerfile" 'COMPOSER_VERSION='
      excludes "$dockerfile" 'NPM_VERSION='
      excludes "$dockerfile" 'xdebug'
      [[ ! -e "$directory/zz-xdebug-settings.ini" ]] || fail 'normal image received development config'
    fi
  done <"$scratch/contexts"

}
check_contexts

snapshot >"$scratch/before"
mapfile -t selectors < <(jq -r 'keys[] + "/"' versions.json)
./apply-templates.sh "${selectors[@]}" >"$scratch/repeat.log"
snapshot >"$scratch/after"
cmp "$scratch/before" "$scratch/after"
if ./apply-templates.sh unknown/state >"$scratch/invalid.log" 2>&1; then fail 'unknown selector succeeded'; fi
snapshot >"$scratch/after"
cmp "$scratch/before" "$scratch/after"

# Even a failed render must leave every previously generated context unchanged.
printf '\n{{ error("intentional test failure") }}\n' >>Dockerfile.template
snapshot >"$scratch/before"
if ./apply-templates.sh >"$scratch/broken.log" 2>&1; then fail 'broken template succeeded'; fi
snapshot >"$scratch/after"
cmp "$scratch/before" "$scratch/after"

# An isolated synthetic prerelease covers creation without an existing stable folder.
prepare "$scratch/prerelease"
if [[ -f .jq-template.awk ]]; then cp .jq-template.awk "$scratch/prerelease/"; fi
jq --slurpfile helper "$repo/versions-helper.json" --arg fixture synthetic \
  -f "$repo/tests/fixtures.jq" "${TEST_VERSIONS_FILE:-$repo/versions.json}" \
  | jq 'with_entries(select(.value.states | has("stable") | not)) | .[] |= (
      .phpVersions = {(.php): .phpVersions[.php]}
      | .states[] |= (.packageType = "tar.gz" | .package = "https://example.invalid/joomla.tar.gz"))' \
  >"$scratch/prerelease/versions.json"
cd "$scratch/prerelease"
selector="$(jq -r 'to_entries[0] | .key + "/" + (.value.states | keys[0])' versions.json)"
./apply-templates.sh "$selector/" >"$scratch/prerelease.log"
check_contexts
[[ ! -d "${selector%/*}/stable" ]] || fail 'prerelease-only series generated a stable directory'
while IFS= read -r file; do
  contains "$file" 'tar -xf joomla.tar.gz -C /usr/src/joomla'
done < <(find "${selector%/*}" -name Dockerfile)
echo 'Template tests passed.'
