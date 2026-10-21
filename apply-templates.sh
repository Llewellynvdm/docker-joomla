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

jqt='.jq-template.awk'
if [[ -n "${BASHBREW_SCRIPTS:-}" ]]; then
  jqt="$BASHBREW_SCRIPTS/jq-template.awk"
elif [[ ! -s "$jqt" ]]; then
  curl --fail --silent --show-error --location --retry 3 \
    'https://raw.githubusercontent.com/docker-library/bashbrew/5f0c26381fb7cc78b2d217d58007800bdcfbcfa1/scripts/jq-template.awk' \
    -o "$staging/jq-template.awk"
  echo "94821535d351a86f6f634d2e7de9f23c81836ca23cc7c0a3de08416922ccda40  $staging/jq-template.awk" | sha256sum --check --status
  mv "$staging/jq-template.awk" "$jqt"
fi
[[ -s "$jqt" ]] || { echo "Template engine not found: $jqt" >&2; exit 1; }
if [[ -z "${BASHBREW_SCRIPTS:-}" ]]; then
  echo "94821535d351a86f6f634d2e7de9f23c81836ca23cc7c0a3de08416922ccda40  $jqt" | sha256sum --check --status
fi

generated_warning() {
  cat <<'EOH'
#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#
EOH
}

joomlaMaintainers="$(jq -cr 'map(.firstname + " " + .lastname + " <" + .email + "> (@" + .github + ")") | join(", ")' maintainers.json)"
export joomlaMaintainers
directories=()

while IFS=$'\t' read -r version state; do
  export version state
  details="$(jq -c --arg series "$version" '.[$series]' versions.json)"
  release="$(jq -c --arg state "$state" '.states[$state]' <<<"$details")"
  joomlaVersion="$(jq -r '.version' <<<"$release")"
  joomlaSha512="$(jq -r '.sha512' <<<"$release")"
  joomlaPackage="$(jq -r '.package' <<<"$release")"
  joomlaPackageType="$(jq -r '.packageType' <<<"$release")"
  export joomlaVersion joomlaSha512 joomlaPackage joomlaPackageType

  docker_entrypoint='docker-entrypoint.sh'
  if [[ -f "docker-entrypoint-$version.sh" ]]; then
    docker_entrypoint="docker-entrypoint-$version.sh"
  fi

  mapfile -t phpVersions < <(jq -r '.phpVersions | keys[]' <<<"$details")
  mapfile -t variants < <(jq -r '.variants[]' <<<"$details")
  developmentVariants=(0)
  if jq -e '.development != null' <<<"$details" >/dev/null; then
    developmentVariants+=(1)
  fi

  for phpVersion in "${phpVersions[@]}"; do
    export phpVersion
    peclValues="$(jq -c --arg php "$phpVersion" '.phpVersions[$php].pecl' <<<"$details")"
    pecl_imagick="$(jq -r '.imagick' <<<"$peclValues")"
    pecl_APCu="$(jq -r '.APCu' <<<"$peclValues")"
    pecl_memcached="$(jq -r '.memcached' <<<"$peclValues")"
    pecl_redis="$(jq -r '.redis' <<<"$peclValues")"
    export pecl_imagick pecl_APCu pecl_memcached pecl_redis

    for variant in "${variants[@]}"; do
      export variant
      for development in "${developmentVariants[@]}"; do
        export development
        dir="$version/$state/php$phpVersion/$variant"
        if [[ "$development" == 1 ]]; then
          dir+='-dev'
          composerVersion="$(jq -r '.development.composer.version' <<<"$details")"
          composerSha256="$(jq -r '.development.composer.sha256' <<<"$details")"
          pieVersion="$(jq -r '.development.pie.version' <<<"$details")"
          pieSha256="$(jq -r '.development.pie.sha256' <<<"$details")"
          xdebugVersion="$(jq -r '.development.xdebug.version' <<<"$details")"
          xdebugSha256="$(jq -r '.development.xdebug.sha256' <<<"$details")"
          xdebugPackage="$(jq -r '.development.xdebug.package' <<<"$details")"
          npmVersion="$(jq -r '.development.npm.version' <<<"$details")"
          npmSha256="$(jq -r '.development.npm.sha256' <<<"$details")"
          export composerVersion composerSha256 pieVersion pieSha256 xdebugVersion xdebugSha256 xdebugPackage npmVersion npmSha256
        fi

        mkdir -p "$staging/$dir"
        cp -p "$docker_entrypoint" "$staging/$dir/docker-entrypoint.sh"
        cp -p makedb.php "$staging/$dir/makedb.php"
        if [[ "$development" == 1 ]]; then
          cp -p development/zz-joomla-development.ini development/zz-xdebug-settings.ini "$staging/$dir/"
        fi
        {
          generated_warning
          gawk -f "$jqt" Dockerfile.template
        } >"$staging/$dir/Dockerfile"
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
