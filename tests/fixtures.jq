# Tests use versions.json; TEST_VERSIONS_FILE can select another resolved snapshot.
# Only the legacy format needs the helper's
# PECL/tool pins, which were not recorded in versions.json before this migration.
with_entries(
  .key as $series | .value as $old
  | if .value.states != null then . else
      .value = ($helper[0][$series]
        | .php = $old.php | .variant = $old.variant | .variants = $old.variants
        | .phpVersions |= with_entries(select(.key as $php | $old.phpVersions | index($php)))
        | .states = {stable: ($old | {
            version, package, packageType, sha512,
            aliases: ([$series] + (.aliases // []) | unique)
          })})
    end
)
| if $fixture == "current" then .
  elif $fixture == "synthetic" then
    # Isolated fake releases exercise states missing from the current matrix.
    # PHP settings come from that matrix; packages and tools are never downloaded.
    (to_entries[0].value
      | .packageType = "tar.zst"
      | .development = {
          composer: {version: "100.0.0", sha256: ("0" * 64)},
          xdebug: {version: "100.0.0", sha256: ("0" * 64)}
        }
      | .states = {
          stable: {version: "100.0.0", aliases: ["100.0", "100", "latest"]},
          alpha: {version: "100.0.1-alpha1", aliases: ["100.0-alpha"]},
          beta: {version: "100.0.1-beta1", aliases: ["100.0-beta"]},
          rc: {version: "100.0.1-rc1", aliases: ["100.0-rc"]}
        }) as $seed
    | {"100.0": $seed, "101.0": ($seed | .states = {
        alpha: {version: "101.0.0-alpha1", aliases: []}
      })}
    | map_values(.states |= map_values(. + {
        packageType: "tar.zst", package: ("https://example.invalid/" + .version + ".tar.zst"),
        sha512: ("0" * 128)
      }))
  else error("unknown test fixture: " + $fixture) end
