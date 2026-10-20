#!/usr/bin/env bash
set -Eeuo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
fixture="$scratch/repo"
mkdir -p "$fixture/scripts" "$fixture/development"
cp "$repo/apply-templates.sh" "$repo/Dockerfile.template" "$repo/docker-entrypoint.sh" \
  "$repo/makedb.php" "$repo/maintainers.json" "$fixture/"
cp "$repo/scripts/validate-config.jq" "$fixture/scripts/"
cp "$repo/development/"*.ini "$fixture/development/"
if [[ -f "$repo/.jq-template.awk" ]]; then
  cp "$repo/.jq-template.awk" "$fixture/"
fi

# These package URLs/checksums are fixtures: templating must never fetch Joomla.
printf -v packageHash '%0128d' 0
jq --arg sha512 "$packageHash" '
  with_entries(.value.states |= with_entries(.value += {
    package: "https://example.invalid/joomla.tar.zst",
    packageType: "tar.zst",
    sha512: $sha512
  }))
' "$repo/versions-helper.json" >"$fixture/versions.json"
# The resolved version file must be the only release/tool configuration input.
printf 'this helper must not be read by apply-templates.sh\n' >"$fixture/versions-helper.json"

fail() { echo "FAIL: $*" >&2; exit 1; }
contains() { grep -Fq -- "$2" "$1" || fail "$1 does not contain: $2"; }
excludes() { if grep -Fq -- "$2" "$1"; then fail "$1 unexpectedly contains: $2"; fi; }

cd "$fixture"
mkdir -p retired/php8.4/apache
printf 'maintainer-owned historical context\n' >retired/php8.4/apache/Dockerfile
./apply-templates.sh >"$scratch/first.log"
expected="$(jq '[.[] | (.phpVersions | length) * (.variants | length) * (.states | length) * (if .development == null then 1 else 2 end)] | add' versions.json)"
actual="$(find . -name Dockerfile -type f | wc -l)"
[[ "$actual" -eq "$((expected + 1))" ]] || fail "expected $expected active contexts and one retained context, got $actual"
contains retired/php8.4/apache/Dockerfile 'maintainer-owned historical context'

normal='6.2/stable/php8.4/apache/Dockerfile'
dev='6.2/stable/php8.4/apache-dev/Dockerfile'
alpine='6.2/stable/php8.4/fpm-alpine-dev/Dockerfile'
contains "$normal" 'FROM php:8.4-apache'
excludes "$normal" 'COMPOSER_VERSION='
excludes "$normal" 'xdebug'
contains "$dev" 'FROM php:8.4-apache'
excludes "$dev" 'FROM php:8.4-apache-dev'
contains "$dev" 'CMD ["apache2-foreground"]'
contains "$dev" 'a2enmod rewrite expires'
contains "$dev" "COMPOSER_VERSION=$(jq -r '.["6.2"].development.composer.version' versions.json)"
contains "$dev" "COMPOSER_SHA256=$(jq -r '.["6.2"].development.composer.sha256' versions.json)"
contains "$dev" "XDEBUG_VERSION=$(jq -r '.["6.2"].development.xdebug.version' versions.json)"
contains "$dev" "XDEBUG_SHA256=$(jq -r '.["6.2"].development.xdebug.sha256' versions.json)"
contains "$dev" 'docker-php-ext-enable --ini-name zz-xdebug.ini xdebug'
contains "$dev" 'JOOMLA_XDEBUG_CLIENT_HOST=host.docker.internal'
contains "$dev" 'JOOMLA_XDEBUG_CLIENT_PORT=9003'
contains "$dev" 'XDEBUG_MODE=develop,debug'
excludes "$dev" 'XDEBUG_CONFIG'
excludes "$dev" 'EXPOSE 9003'
contains "$alpine" 'FROM php:8.4-fpm-alpine'
# shellcheck disable=SC2016 # Inspect the literal variable in the Dockerfile.
contains "$alpine" '$PHPIZE_DEPS linux-headers zlib-dev'
contains "$alpine" 'apk del --no-network .xdebug-build-deps'
contains "$alpine" 'CMD ["php-fpm"]'
excludes "$alpine" 'a2enmod'
contains 6.2/stable/php8.4/apache/Dockerfile 'docker-php-ext-enable opcache'
excludes 6.2/stable/php8.5/apache-dev/Dockerfile 'docker-php-ext-enable opcache'
[[ ! -e 5.4/stable/php8.2/apache-dev ]] || fail 'unexpected development context for Joomla 5.4'
[[ ! -e 6.2/stable/php8.4/apache/zz-xdebug-settings.ini ]] || fail 'normal image received development config'
cmp development/zz-xdebug-settings.ini 6.2/stable/php8.4/apache-dev/zz-xdebug-settings.ini
cmp development/zz-joomla-development.ini 6.2/stable/php8.4/apache-dev/zz-joomla-development.ini
[[ -x 6.2/stable/php8.4/apache-dev/docker-entrypoint.sh ]] || fail 'entrypoint lost executable mode'

find . -type f -print0 | sort -z | xargs -0 sha256sum >"$scratch/first.sha256"
# Directory-style series selectors keep the trailing-slash behavior of update.
mapfile -t seriesDirectories < <(jq -r 'keys[] + "/"' versions.json)
./apply-templates.sh "${seriesDirectories[@]}" >"$scratch/second.log"
find . -type f -print0 | sort -z | xargs -0 sha256sum >"$scratch/second.sha256"
cmp "$scratch/first.sha256" "$scratch/second.sha256" || fail 'repeated generation changed files'

# A new prerelease-only series must not require a pre-created directory.
jq --arg sha512 "$packageHash" '
  .["7.0"] = .["6.2"]
  | .["7.0"].phpVersions |= with_entries(select(.key == "8.4"))
  | .["7.0"].variants = ["apache"]
  | .["7.0"].states = {alpha: {
      version: "7.0.0-alpha1", aliases: [], packageType: "tar.gz",
      package: "https://example.invalid/joomla.tar.gz", sha512: $sha512
    }}
' versions.json >"$scratch/versions.json"
mv "$scratch/versions.json" versions.json
# State selectors accept the same optional trailing slash.
./apply-templates.sh 7.0/alpha/ >"$scratch/alpha.log"
contains 7.0/alpha/php8.4/apache-dev/Dockerfile 'ENV JOOMLA_VERSION=7.0.0-alpha1'
contains 7.0/alpha/php8.4/apache-dev/Dockerfile 'tar -xf joomla.tar.gz -C /usr/src/joomla'
[[ ! -e 7.0/stable ]] || fail 'prerelease-only series generated a stable directory'

before="$(sha256sum "$dev")"
if ./apply-templates.sh 6.2/unknown >"$scratch/invalid.log" 2>&1; then
  fail 'unknown release selector succeeded'
fi
[[ "$before" == "$(sha256sum "$dev")" ]] || fail 'invalid selector changed an existing context'

# A failed render must not publish any partially generated Dockerfile.
printf '\n{{ error("intentional test failure") }}\n' >>Dockerfile.template
if ./apply-templates.sh 6.2/stable >"$scratch/broken.log" 2>&1; then
  fail 'broken template succeeded'
fi
[[ "$before" == "$(sha256sum "$dev")" ]] || fail 'failed render changed an existing context'
[[ -z "$(find . -maxdepth 1 -name '.template-staging.*' -print)" ]] || fail 'temporary staging directory leaked'

echo 'Template fixtures passed.'
