#!/usr/bin/env bash
set -Eeuo pipefail
repository="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

# Exercise the active matrix, then isolated releases for states it may not contain.
for fixture in current synthetic; do
  jq --slurpfile helper "$repository/versions-helper.json" --arg fixture "$fixture" \
    -f "$repository/tests/fixtures.jq" "${TEST_VERSIONS_FILE:-$repository/versions.json}" >"$temporary/config.json"
  jq -f "$repository/scripts/tags.jq" "$temporary/config.json" >"$temporary/plan.json"
  jq -e --slurpfile config "$temporary/config.json" '
    . as $plan | $config[0] as $config
    | ([.[] | .tags[]] | length == (unique | length))
      and (length == ([$config[] | (.phpVersions | length) * (.variants | length)
        * (.states | length) * (if .development == null then 1 else 2 end)] | add))
      and all(.[]; . as $context | $config[.series] as $settings
        | $settings.states[.state] as $release
        | ([$release.version] + ($release.aliases // [] | map(tostring)) | unique) as $names
        | (.php == $settings.php and .variant == $settings.variant) as $default
        | [$names[] as $name
            | (if $name == "latest" then "" else $name + "-" end) as $prefix
            | ($prefix + "php" + $context.php + "-" + $context.variant),
              (if $default then $name, ($prefix + $context.variant), ($prefix + "php" + $context.php) else empty end)
            | if $context.development then (if . == "latest" then "dev" else . + "-dev" end) else . end
          ] | unique as $expected
        | $context.directory == ($context.series + "/" + $context.state + "/php" + $context.php + "/" + $context.variant
            + (if $context.development then "-dev" else "" end))
          and $context.version == $release.version
          and ($context.tags | sort) == $expected)
      and all(.[] | select(.development == false); . as $normal
        | ($plan | map(select(.directory == ($normal.directory + "-dev")))) as $siblings
        | if $config[.series].development == null then $siblings == []
          else ($siblings | length) == 1 and $siblings[0].tags ==
            (.tags | map(if . == "latest" then "dev" else . + "-dev" end)) end)
  ' "$temporary/plan.json" >/dev/null
done

# Synthetic series are isolated from maintained releases and never downloaded.
for expression in '.["101.0"].states.alpha.aliases = []' 'del(.["101.0"].states.alpha.aliases)' '.["101.0"].states.alpha.aliases = null'; do
  jq "$expression" "$temporary/config.json" | jq -f "$repository/scripts/tags.jq" >"$temporary/actual.json"
  cmp "$temporary/plan.json" "$temporary/actual.json"
done
reject() {
  local expression="$1" diagnostic="$2"
  jq "$expression" "$temporary/config.json" >"$temporary/invalid.json"
  if jq -f "$repository/scripts/tags.jq" "$temporary/invalid.json" >"$temporary/output" 2>"$temporary/error"; then
    printf 'FAIL: accepted %s\n' "$expression" >&2; exit 1
  fi
  [[ ! -s "$temporary/output" ]]
  grep -Fq "$diagnostic" "$temporary/error"
}
reject '.["100.0"].variant = [.["100.0"].variant]' 'default variant must be a string'
reject '.["100.0"].states.alpha.aliases = ""' 'aliases must be an array'
reject '.["100.0"].states.alpha.aliases = false' 'aliases must be an array'
reject '.["100.0"].states.alpha.aliases = ["100.0"]' 'prerelease aliases must retain their release state'
reject '.["100.0"].states.rc.aliases = ["latest"]' 'prerelease aliases must retain their release state'
reject '.["100.0"].states.stable.aliases += ["latest-dev"]' 'invalid or reserved release alias'
reject '.["100.0"].states.stable.aliases += ["dev"]' 'invalid or reserved release alias'
reject '.["100.0"].states.alpha.version = .["100.0"].states.beta.version' 'version does not match its series and state'
reject '.["100.0"].states.alpha.version = "not-a-version"' 'version does not match its series and state'
reject '.["101.0"].states = {stable: {version:"101.0.0", aliases:["latest"]}}' 'tag collision'
# A release alias can collide with another alias only after suffix expansion.
reject '.["101.0"].states = {stable: {version:"101.0.0", aliases:["100.0.0-php" + .["100.0"].php]}}' 'tag collision'
reject '.["100.0"].states.stable.aliases += [("x" * 128)]' 'expanded image tag is invalid'

printf 'Tag generation tests passed.\n'
