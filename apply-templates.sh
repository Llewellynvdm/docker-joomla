#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

if [[ ! -f versions.json ]]; then
  echo 'versions.json not found; run ./versions.sh first.' >&2
  exit 1
fi

# Resolve and validate every selector before writing any build context.
jq -e --arg mode resolved -f scripts/validate-config.jq versions.json >/dev/null
selectors="$(jq -cn --args '$ARGS.positional' -- "$@")"
tracks="$(jq -er --argjson selectors "$selectors" '
  . as $config
  | [if $selectors == [] then
       to_entries[] | .key as $series | .value.states | keys[] | [$series, .]
     else
       $selectors[] | rtrimstr("/") | split("/") as $parts
       | if ($parts | length) == 1 and $config[$parts[0]] != null then
           $config[$parts[0]].states | keys[] | [$parts[0], .]
         elif ($parts | length) == 2 and $config[$parts[0]].states[$parts[1]] != null then
           $parts
         else error("Unknown release selector: " + ($parts | join("/"))) end
     end]
  | unique | .[] | @tsv
' versions.json)"

staging="$(mktemp -d .template-staging.XXXXXXXX)"
trap 'rm -rf "$staging"' EXIT

directories=()

while IFS=$'\t' read -r version state; do
  export version state
  details="$(jq -c --arg series "$version" '.[$series]' versions.json)"
  docker_entrypoint='docker-entrypoint.sh'
  if [[ -f "docker-entrypoint-$version.sh" ]]; then
    docker_entrypoint="docker-entrypoint-$version.sh"
  fi

  mapfile -t phpVersions < <(jq -r '.phpVersions | keys[]' <<<"$details")
  mapfile -t variants < <(jq -r '.variants[]' <<<"$details")
  for phpVersion in "${phpVersions[@]}"; do
    developmentVariants=(0)
    if jq -e --arg php "$phpVersion" '.phpVersions[$php].dev != null' <<<"$details" >/dev/null; then
      developmentVariants+=(1)
    fi
    for variant in "${variants[@]}"; do
      export variant
      for development in "${developmentVariants[@]}"; do
        export development
        dir="$version/$state/php$phpVersion/$variant"
        if [[ "$development" == 1 ]]; then
          dir+='-dev'
        fi

        mkdir -p "$staging/$dir"
        cp -p "$docker_entrypoint" "$staging/$dir/docker-entrypoint.sh"
        cp -p makedb.php "$staging/$dir/makedb.php"
        python3 scripts/render-dockerfile.py versions.json "$version" "$state" "$phpVersion" "$variant" "$development" Dockerfile.template >"$staging/$dir/Dockerfile"
        directories+=("$dir")
      done
    done
  done
done <<<"$tracks"

# Publish only after all selected Dockerfiles rendered successfully. Old contexts
# and unrelated files are deliberately left alone; removal is a maintainer task.
for dir in "${directories[@]}"; do
  mkdir -p "$dir"
  for file in "$staging/$dir/"*; do
    mv -f "$file" "$dir/${file##*/}"
  done
  echo "processed $dir"
done
