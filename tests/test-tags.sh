#!/usr/bin/env bash
set -Eeuo pipefail

repository="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

cat >"$temporary/versions.json" <<'JSON'
{
  "6.2": {
    "php": "8.4",
    "phpVersions": {"8.3": {}, "8.4": {}},
    "variant": "apache",
    "variants": ["apache", "fpm-alpine", "fpm"],
    "development": {},
    "states": {
      "stable": {"version": "6.2.0", "aliases": ["6.2", 6, "latest"]},
      "alpha": {"version": "6.2.1-alpha1", "aliases": ["6.2-alpha"]},
      "beta": {"version": "6.2.1-beta1", "aliases": ["6.2-beta"]},
      "rc": {"version": "6.2.1-rc1", "aliases": ["6.2-rc"]}
    }
  },
  "7.0": {
    "php": "8.4",
    "phpVersions": {"8.4": {}},
    "variant": "apache",
    "variants": ["apache"],
    "development": {},
    "states": {"alpha": {"version": "7.0.0-alpha1", "aliases": []}}
  }
}
JSON

jq -f "$repository/scripts/tags.jq" "$temporary/versions.json" >"$temporary/plan.json"
jq -e 'length == 50' "$temporary/plan.json" >/dev/null

# Keep the current stable aliases exactly, including their default-PHP rules.
jq -e '
  map(select(.directory == "6.2/stable/php8.4/apache"))[0].tags == [
    "6.2.0", "6.2", "6", "latest",
    "6.2.0-apache", "6.2-apache", "6-apache", "apache",
    "6.2.0-php8.4", "6.2-php8.4", "6-php8.4", "php8.4",
    "6.2.0-php8.4-apache", "6.2-php8.4-apache", "6-php8.4-apache", "php8.4-apache"
  ]
' "$temporary/plan.json" >/dev/null
jq -e '
  map(select(.directory == "6.2/stable/php8.3/apache"))[0].tags == [
    "6.2.0-php8.3-apache", "6.2-php8.3-apache", "6-php8.3-apache", "php8.3-apache"
  ]
' "$temporary/plan.json" >/dev/null

# Every normal image has exactly its development aliases, latest becoming dev.
jq -e '
  . as $plan | all(.[] | select(.development == false);
    . as $normal | ($plan | map(select(.directory == ($normal.directory + "-dev")))[0].tags)
    == ($normal.tags | map(if . == "latest" then "dev" else . + "-dev" end)))
' "$temporary/plan.json" >/dev/null
jq -e '[.[] | select(.state != "stable") | .tags[]] | all(.[]; test("-(alpha|beta|rc)"))' \
  "$temporary/plan.json" >/dev/null
jq -e '[.[] | .tags[]] | (map(select(. == "latest")) | length) == 1 and (map(select(. == "dev")) | length) == 1' \
  "$temporary/plan.json" >/dev/null

# Empty, absent, and null alias lists have identical exact-version behaviour.
for expression in '.["7.0"].states.alpha.aliases = []' 'del(.["7.0"].states.alpha.aliases)' '.["7.0"].states.alpha.aliases = null'; do
  jq "$expression" "$temporary/versions.json" | jq -f "$repository/scripts/tags.jq" >"$temporary/actual.json"
  cmp "$temporary/plan.json" "$temporary/actual.json"
done

reject() {
  local expression="$1" diagnostic="$2"
  jq "$expression" "$temporary/versions.json" >"$temporary/invalid.json"
  if jq -f "$repository/scripts/tags.jq" "$temporary/invalid.json" >"$temporary/output" 2>"$temporary/error"; then
    printf 'FAIL: accepted %s\n' "$expression" >&2
    exit 1
  fi
  [[ ! -s "$temporary/output" ]]
  grep -Fq "$diagnostic" "$temporary/error"
}

reject '.["6.2"].variant = ["apache"]' 'default variant must be a string'
reject '.["6.2"].states.alpha.aliases = ""' 'aliases must be an array'
reject '.["6.2"].states.alpha.aliases = false' 'aliases must be an array'
reject '.["6.2"].states.alpha.aliases = ["6.2"]' 'prerelease aliases must retain their release state'
reject '.["6.2"].states.rc.aliases = ["latest"]' 'prerelease aliases must retain their release state'
reject '.["6.2"].states.stable.aliases += ["latest-dev"]' 'invalid or reserved release alias'
reject '.["6.2"].states.stable.aliases += ["dev"]' 'invalid or reserved release alias'
reject '.["6.2"].states.alpha.version = "6.2.1-beta1"' 'version does not match its series and state'
reject '.["6.2"].states.alpha.version = "not-a-version"' 'version does not match its series and state'
reject '.["6.2"].states.stable.aliases += ["6.2.0-php8.3"]' 'tag collision'
reject '.["7.0"].states = {"stable": {"version": "7.0.0", "aliases": ["latest"]}}' 'tag collision'
reject '.["6.2"].states.stable.aliases += [("x" * 128)]' 'expanded image tag is invalid'

# Leaving old folders on disk is irrelevant: the plan follows only the JSON.
jq 'del(.["6.2"].states.alpha, .["6.2"].states.beta, .["6.2"].development)' "$temporary/versions.json" \
  | jq -f "$repository/scripts/tags.jq" \
  | jq -e 'length == 14 and all(.[] | select(.series == "6.2"); (.state == "stable" or .state == "rc") and .development == false)' >/dev/null

printf 'Tag generation tests passed.\n'
