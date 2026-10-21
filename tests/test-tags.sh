#!/usr/bin/env bash
set -Eeuo pipefail
repository="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

trap 'printf "FAIL: %s:%s: %s\n" "${BASH_SOURCE[0]}" "$LINENO" "$BASH_COMMAND" >&2' ERR

# Check the maintained matrix without reproducing the tag expansion algorithm.
for fixture in current synthetic; do
  jq --slurpfile helper "$repository/versions-helper.json" --arg fixture "$fixture" \
    -f "$repository/tests/fixtures.jq" "${TEST_VERSIONS_FILE:-$repository/versions.json}" >"$temporary/config.json"
  if [[ "$fixture" == synthetic ]]; then
    # Tag-only fixtures use deliberately fictional PHP versions; no image is built.
    jq 'map_values(.php = "100.0" | .phpVersions = {"100.0": {}, "100.1": {}}
      | .variant = "apache" | .variants = ["apache", "fpm"])' "$temporary/config.json" >"$temporary/synthetic.json"
    mv "$temporary/synthetic.json" "$temporary/config.json"
  fi
  jq -f "$repository/scripts/tags.jq" "$temporary/config.json" >"$temporary/plan.json"
  jq -e --slurpfile config "$temporary/config.json" '
    . as $plan | $config[0] as $config
    | ([.[] | .tags[]] | length == (unique | length))
      and ([.[].directory] | length == (unique | length))
      and (length == ([$config[] | (.phpVersions | length) * (.variants | length)
        * (.states | length) * (if .development == null then 1 else 2 end)] | add))
      and all(.[]; . as $context | .version == $config[.series].states[.state].version
        and ($config[.series].phpVersions | has($context.php))
        and ($config[.series].variants | index($context.variant) != null)
        and .directory == (.series + "/" + .state + "/php" + .php + "/" + .variant
          + (if .development then "-dev" else "" end)))
      and all(.[] | select(.tags | index("latest"));
        .state == "stable" and .development == false
        and .php == $config[.series].php and .variant == $config[.series].variant)
      and all(.[] | select(.development == false); . as $normal
        | ($plan | map(select(.directory == ($normal.directory + "-dev")))) as $siblings
        | if $config[.series].development == null then $siblings == []
          else ($siblings | length) == 1 and $siblings[0].tags ==
            (.tags | map(if . == "latest" then "dev" else . + "-dev" end)) end)
  ' "$temporary/plan.json" >/dev/null
done

# Explicit examples are the tag contract, independent of the production logic.
# Cover stable aliases, every prerelease state, defaults, and nondefault contexts.
cat >"$temporary/expected.json" <<'JSON'
{
  "100.0/stable/php100.0/apache": [
    "100.0.0", "100.0", "100", "latest",
    "100.0.0-apache", "100.0-apache", "100-apache", "apache",
    "100.0.0-php100.0", "100.0-php100.0", "100-php100.0", "php100.0",
    "100.0.0-php100.0-apache", "100.0-php100.0-apache", "100-php100.0-apache", "php100.0-apache"
  ],
  "100.0/alpha/php100.0/apache": [
    "100.0.1-alpha1", "100.0-alpha", "100.0.1-alpha1-apache", "100.0-alpha-apache",
    "100.0.1-alpha1-php100.0", "100.0-alpha-php100.0", "100.0.1-alpha1-php100.0-apache", "100.0-alpha-php100.0-apache"
  ],
  "100.0/beta/php100.1/apache": ["100.0.1-beta1-php100.1-apache", "100.0-beta-php100.1-apache"],
  "100.0/rc/php100.0/fpm": ["100.0.1-rc1-php100.0-fpm", "100.0-rc-php100.0-fpm"],
  "101.0/alpha/php100.0/apache": [
    "101.0.0-alpha1", "101.0.0-alpha1-apache", "101.0.0-alpha1-php100.0", "101.0.0-alpha1-php100.0-apache"
  ]
}
JSON
jq -e --slurpfile expected "$temporary/expected.json" '
  INDEX(.[]; .directory) as $actual
  | $expected[0] | to_entries | all(.[];
    . as $case | ($actual[$case.key].tags | sort) == ($case.value | sort)
    or error("unexpected tags for " + $case.key + ": " + ($actual[$case.key].tags | tojson)))
' "$temporary/plan.json" >/dev/null

# The default is configurable, not implicitly Apache or the first PHP version.
jq '."100.0".php = "100.1" | ."100.0".variant = "fpm"' "$temporary/config.json" \
  | jq -f "$repository/scripts/tags.jq" \
  | jq -e 'map(select(.tags | index("latest")))
      | length == 1 and .[0].directory == "100.0/stable/php100.1/fpm"' >/dev/null

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
  [[ ! -s "$temporary/output" ]] || { printf 'FAIL: invalid config emitted a partial tag plan: %s\n' "$expression" >&2; exit 1; }
  grep -Fq "$diagnostic" "$temporary/error" || { cat "$temporary/error" >&2; printf 'FAIL: expected diagnostic: %s\n' "$diagnostic" >&2; exit 1; }
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
