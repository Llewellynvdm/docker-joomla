#!/usr/bin/env bash
set -Eeuo pipefail

# Emit one Dockerfile directly from resolved JSON; no template engine is needed.
# Shell expressions below are deliberately emitted for the image build to run.
# shellcheck disable=SC2016
render_dockerfile() (
  set -Eeuo pipefail
  if (( $# != 6 )); then
    echo 'render_dockerfile requires CONFIG SERIES STATE PHP VARIANT DEVELOPMENT' >&2
    exit 1
  fi
  configuration=$1 series=$2 state=$3 php=$4 variant=$5 development=$6
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  selected="$(jq -ce --arg series "$series" --arg state "$state" --arg php "$php" \
    --arg variant "$variant" --arg development "$development" '
    # Append unique package entries, but replace each configured file as a unit.
    def merge($other):
      reduce ($other | to_entries[]) as $entry (.;
        $entry.key as $key | $entry.value as $value
        | .[$key] = (
            if $key == "config" then (.[$key] // {}) + $value
            elif (.[$key] | type) == "object" and ($value | type) == "object" then
              .[$key] | merge($value)
            elif (.[$key] | type) == "array" and ($value | type) == "array" then
              reduce (.[$key] + $value)[] as $item
                ([]; if index($item) == null then . + [$item] else . end)
            else $value end));
    .[$series] as $settings
    | $settings.phpVersions[$php]
    | if $development == "1" then merge(.dev) else . end
    | merge(.variants[$variant])
    | {image: ., release: $settings.states[$state]}
  ' "$configuration")"
  image="$(jq -c '.image' <<<"$selected")"
  release="$(jq -c '.release' <<<"$selected")"

  quote() {
    if [[ $1 =~ ^[a-zA-Z0-9_@%+=:,./-]+$ ]]; then
      printf '%s' "$1"
    else
      printf "'%s'" "${1//\'/\'\"\'\"\'}"
    fi
  }
  words() {
    local separator='' value
    for value; do
      printf '%s' "$separator"
      quote "$value"
      separator=' '
    done
  }
  quote_configure() {
    local value=$1 prefix result=''
    # Only this exact placeholder may expand during the image build.
    while [[ $value == *'${DEB_BUILD_MULTIARCH}'* ]]; do
      prefix="${value%%'${DEB_BUILD_MULTIARCH}'*}"
      if [[ -n $prefix ]]; then result+="$(quote "$prefix")"; fi
      result+='"${DEB_BUILD_MULTIARCH}"'
      value="${value#*'${DEB_BUILD_MULTIARCH}'}"
    done
    if [[ -n $value ]]; then result+="$(quote "$value")"; fi
    printf '%s' "$result"
  }
  json_words() {
    jq -r "$1 | map(tostring | if test(\"^[a-zA-Z0-9_@%+=:,./-]+$\") then . else @sh end) | join(\" \")" <<<"$image"
  }
  steps=()
  step() { steps+=("$1"); }

  manager=apt
  if [[ $variant == *alpine* ]]; then manager=apk; fi
  if [[ $manager == apt ]]; then
    step 'export DEBIAN_FRONTEND=noninteractive'
    step 'apt-get update'
    packages="$(json_words '.apt // []')"
    if [[ -n $packages ]]; then step "apt-get install -y --no-install-recommends $packages"; fi
    step 'savedAptMark="$(apt-mark showmanual)"'
    step 'apt-get install -y --no-install-recommends $PHPIZE_DEPS '"$(json_words '.build.apt')"
    step 'DEB_BUILD_MULTIARCH="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"'
  else
    packages="$(json_words '.apk // []')"
    if [[ -n $packages ]]; then step "apk add --no-cache $packages"; fi
    step 'apk add --no-cache --virtual .build-deps $PHPIZE_DEPS '"$(json_words '.build.apk')"
  fi
  while IFS= read -r extension; do
    name="$(jq -r '.key' <<<"$extension")"
    args=()
    while IFS= read -r value; do
      value="$(jq -r '.' <<<"$value")"
      if [[ $value == *'${DEB_BUILD_MULTIARCH}'* ]]; then
        # Resolve this build fact inside the target image, not on the host.
        args+=("$(quote_configure "$value")")
      else
        args+=("$(quote "$value")")
      fi
    done < <(jq -c '.value[]' <<<"$extension")
    step "docker-php-ext-configure $(quote "$name") ${args[*]}"
  done < <(jq -c '.extensions.configure // {} | to_entries[]' <<<"$image")
  packages="$(json_words '.extensions.install // []')"
  if [[ -n $packages ]]; then step 'docker-php-ext-install -j "$(nproc)" '"$packages"; fi

  fetch="curl --fail --show-error --silent --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https'"
  temporary=()
  while IFS= read -r download; do
    name="$(jq -r '.key' <<<"$download")"
    item="$(jq -c '.value' <<<"$download")"
    destination="$(jq -r '.destination' <<<"$item")"
    type="$(jq -r '.type' <<<"$item")"
    target="/tmp/download-$name"
    if [[ $type == binary ]]; then target=$destination; fi
    step "$fetch $(quote "$(jq -r '.package' <<<"$item")") -o $(quote "$target")"
    step "echo $(quote "$(jq -r '.sha256' <<<"$item")  $target") | sha256sum -c -"
    if [[ $type == binary ]]; then
      step "chmod 0755 $(quote "$target")"
    else
      step "mkdir -p $(quote "$destination")"
      step "tar -xzf $(quote "$target") -C $(quote "$destination") --strip-components=1 --no-same-owner"
      step "rm -f $(quote "$target")"
    fi
    while IFS= read -r link; do
      step "ln -s $(quote "$(jq -r '.value' <<<"$link")") $(quote "$(jq -r '.key' <<<"$link")")"
    done < <(jq -c '.links // {} | to_entries[]' <<<"$item")
    if jq -e '.temporary == true' <<<"$item" >/dev/null; then temporary+=("$destination"); fi
  done < <(jq -c '.download // {} | to_entries[]' <<<"$image")
  for installer in pie pecl; do
    while IFS= read -r package; do
      name="$(jq -r '.key' <<<"$package")"
      version="$(jq -r '.value' <<<"$package")"
      if [[ $installer == pie ]]; then
        # PIE uses docker-php-ext-enable in the official PHP image.
        step "PIE_WORKING_DIRECTORY=/tmp/joomla-pie $(quote "$(jq -r '.download.pie.destination' <<<"$image")")"' install --no-interaction --no-cache --make-parallel-jobs="$(nproc)" '"$(quote "$name:$version")"
      else
        step "printf '\\n' | pecl install $(quote "$name-$version")"
      fi
    done < <(jq -c --arg installer "$installer" '.[$installer] // {} | to_entries[]' <<<"$image")
  done
  packages="$(json_words '.extensions.enable // []')"
  if [[ -n $packages ]]; then step "docker-php-ext-enable $packages"; fi
  packages="$(json_words '.npm // {} | to_entries | map(.key + "@" + .value)')"
  if [[ -n $packages ]]; then
    step "npm_config_cache=/tmp/joomla-npm npm install --global --prefix /usr/local --no-audit --no-fund --engine-strict $packages"
    step 'hash -r'
  fi
  step "rm -rf $(words "${temporary[@]}" /tmp/joomla-pie /tmp/joomla-npm /tmp/pear /root/.cache)"
  package_type="$(jq -r '.packageType' <<<"$release")"
  archive="/tmp/joomla.$package_type"
  package="$(jq -r '.package' <<<"$release")"
  sha512="$(jq -r '.sha512' <<<"$release")"
  tar_option=''
  if [[ $package_type == tar.zst ]]; then tar_option='--zstd '; fi
  step "$fetch $(quote "$package") -o $(quote "$archive")"
  step "echo $(quote "$sha512  $archive") | sha512sum -c -"
  step 'mkdir -p /usr/src/joomla'
  step "tar ${tar_option}-xf $(quote "$archive") -C /usr/src/joomla"
  step "rm -f $(quote "$archive")"
  step 'chown -R www-data:www-data /usr/src/joomla'
  step 'extDir="$(php-config --extension-dir)"'

  # Keep each cleanup pipeline together on one continued Dockerfile line.
  cleanup="$(<"$script_dir/scripts/cleanup-$manager.inc")"$'\n'
  continuation=$'\\\n'
  cleanup="${cleanup//"; $continuation"/$';\n'}"
  cleanup="${cleanup//"$continuation"/ }"
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    if [[ -n $line && $line != \#* ]]; then step "${line%;}"; fi
  done <<<"$cleanup"
  step '! { ldd "$extDir"/*.so | grep "not found"; }'
  step 'err="$(php --version 3>&1 1>&2 2>&3)"'
  step '[ -z "$err" ]'
  while IFS= read -r config; do
    path="$(jq -r '.key' <<<"$config")"
    directory="${path%/*}"
    step "mkdir -p $(quote "${directory:-/}")"
    mapfile -t lines < <(jq -c '.value[]' <<<"$config")
    values=()
    for line in "${lines[@]}"; do values+=("$(jq -r '.' <<<"$line")"); done
    step "printf '%s\\n' $(words "${values[@]}") > $(quote "$path")"
  done < <(jq -c '.config // {} | to_entries[]' <<<"$image")
  if jq -e '.apache != null' <<<"$image" >/dev/null; then
    step "a2enmod $(json_words '.apache.modules')"
    step "a2enconf $(json_words '.apache.enable')"
    if jq -e '.apache.remoteAddress == true' <<<"$image" >/dev/null; then
      step "find /etc/apache2 -type f -name '*.conf' -exec sed -ri 's/([[:space:]]*LogFormat[[:space:]]+\"[^\"]*)%h([^\"]*\")/\\1%a\\2/g' '{}' +"
    fi
  fi

  printf '# NOTE: THIS DOCKERFILE IS GENERATED VIA "build.sh". DO NOT EDIT.\n'
  printf 'FROM %s\n' "$(jq -r '.base' <<<"$image")"
  printf 'LABEL maintainer="%s"\n\n' "$(jq -r 'map("\(.firstname) \(.lastname) <\(.email)> (@\(.github))") | join(", ")' maintainers.json)"
  jq -r '.environment | to_entries[] | "ENV \(.key)=\(.value | tojson)"' <<<"$image"
  printf '\nENV JOOMLA_VERSION=%s\nENV JOOMLA_SHA512=%s\n\n' "$(jq -r '.version' <<<"$release")" "$sha512"
  printf 'RUN set -eux'
  for line in "${steps[@]}"; do printf '; \\\n\t%s' "$line"; done
  printf '\n\nVOLUME %s\n' "$(jq -r '.volume | map(tojson) | "[" + join(", ") + "]"' <<<"$image")"
  printf 'WORKDIR %s\n' "$(jq -r '.workdir' <<<"$image")"
  printf 'COPY docker-entrypoint.sh /entrypoint.sh\nCOPY makedb.php /makedb.php\n'
  printf 'ENTRYPOINT %s\n' "$(jq -r '.entrypoint | map(tojson) | "[" + join(", ") + "]"' <<<"$image")"
  printf 'CMD %s\n' "$(jq -r '.command | map(tojson) | "[" + join(", ") + "]"' <<<"$image")"
)

main() (
  cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

  if [[ ! -f versions.json ]]; then
    echo 'versions.json not found; run ./versions.sh first.' >&2
    exit 1
  fi
  # Validate every selector before writing any build context.
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
  staging="$(mktemp -d .build-staging.XXXXXXXX)"
  trap 'rm -rf "$staging"' EXIT
  directories=()
  while IFS=$'\t' read -r version state; do
    details="$(jq -c --arg series "$version" '.[$series]' versions.json)"
    docker_entrypoint='docker-entrypoint.sh'
    if [[ -f "docker-entrypoint-$version.sh" ]]; then docker_entrypoint="docker-entrypoint-$version.sh"; fi
    mapfile -t phpVersions < <(jq -r '.phpVersions | keys[]' <<<"$details")
    mapfile -t variants < <(jq -r '.variants[]' <<<"$details")
    for phpVersion in "${phpVersions[@]}"; do
      developmentVariants=(0)
      if jq -e --arg php "$phpVersion" '.phpVersions[$php].dev != null' <<<"$details" >/dev/null; then
        developmentVariants+=(1)
      fi
      for variant in "${variants[@]}"; do
        for development in "${developmentVariants[@]}"; do
          dir="$version/$state/php$phpVersion/$variant"
          if [[ $development == 1 ]]; then dir+='-dev'; fi
          mkdir -p "$staging/$dir"
          cp -p "$docker_entrypoint" "$staging/$dir/docker-entrypoint.sh"
          cp -p makedb.php "$staging/$dir/makedb.php"
          render_dockerfile versions.json "$version" "$state" "$phpVersion" "$variant" "$development" >"$staging/$dir/Dockerfile"
          directories+=("$dir")
        done
      done
    done
  done <<<"$tracks"

  # Publish only after every selected Dockerfile renders successfully.
  # Old contexts and unrelated files are deliberately left alone.
  for dir in "${directories[@]}"; do
    mkdir -p "$dir"
    for file in "$staging/$dir/"*; do mv -f "$file" "$dir/${file##*/}"; done
    echo "processed $dir"
  done
)

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
