#!/usr/bin/env bash
# Exercise initial deployment TLS policy without requiring a database or Docker.
set -Eeuo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=entrypoint-test \
  -keyout "$tmp/client.key" -out "$tmp/ca.pem" >/dev/null 2>&1
cp "$tmp/ca.pem" "$tmp/client.pem"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_argument() {
  local expected=$1 argument
  for argument in "${joomla_db_encryption_args[@]}"; do
    [[ $argument != "$expected" ]] || return 0
  done
  fail "Missing installer argument: $expected"
}
expect_failure() {
  if ( "$@" ) >"$tmp/failure.log" 2>&1; then
    fail "Unexpected success: $*"
  fi
}
setup() {
  local name
  for name in "${!JOOMLA_@}"; do unset "$name"; done
  # shellcheck source=src/runtime/docker-entrypoint.sh
  source "$root/src/runtime/docker-entrypoint.sh"
  export JOOMLA_WEBROOT="$tmp/$test_name/site"
  export JOOMLA_DB_SSL_DIR="$tmp/$test_name/tls"
  mkdir -p "$JOOMLA_WEBROOT"
  uid=$(id -u); user=$uid; group=$(id -g)
  JOOMLA_DB_TYPE=mysqli
  JOOMLA_DB_HOST=database
}

test_default() {
  joomla_prepare_db_encryption
  [[ $JOOMLA_DB_ENCRYPTION == 0 ]] || fail 'Default mode must be 0'
  [[ ${#joomla_db_encryption_args[@]} == 1 ]] || fail 'Default mode added TLS arguments'
  assert_argument --db-encryption=0
  [[ ! -e $JOOMLA_DB_SSL_DIR ]] || fail 'Default mode created TLS files'
}
test_explicit_zero() {
  JOOMLA_DB_ENCRYPTION=0
  JOOMLA_DB_SSL_CA_FILE=/does/not/exist
  JOOMLA_DB_SSL_CA=ignored
  JOOMLA_DB_SSL_VERIFY_SERVER_CERT=invalid
  joomla_prepare_db_encryption
  [[ ${#joomla_db_encryption_args[@]} == 1 ]] || fail 'Mode 0 added TLS arguments'
  assert_argument --db-encryption=0
}
test_ca_file() {
  JOOMLA_DB_SSL_CA_FILE="$tmp/ca.pem"
  joomla_prepare_db_encryption
  [[ $JOOMLA_DB_ENCRYPTION == 1 ]] || fail 'CA alone must select mode 1'
  assert_argument --db-encryption=1
  assert_argument --db-sslverifyservercert=1
  assert_argument "--db-sslca=$tmp/ca.pem"
  [[ ! -e $JOOMLA_DB_SSL_DIR ]] || fail 'Mounted CA created an unnecessary directory'
  [[ $(bash -c 'printf %s "$JOOMLA_DB_SSL_CA_FILE"') == "$tmp/ca.pem" ]] || fail 'CA file path not exported'
}
test_secret_symlink() {
  ln -s "$tmp/ca.pem" "$tmp/$test_name/rotating-ca.pem"
  cd "$tmp/$test_name"
  JOOMLA_DB_SSL_CA_FILE=rotating-ca.pem
  joomla_prepare_db_encryption
  [[ $JOOMLA_DB_SSL_CA_FILE == "$PWD/rotating-ca.pem" ]] || fail 'Secret mount symlink was resolved to a transient target'
  assert_argument "--db-sslca=$PWD/rotating-ca.pem"
}
test_worker_access() {
  # Simulate root preparing files for a different worker, without needing chown.
  uid=0
  user=$(( $(id -u) + 1 ))
  group=$(( $(id -g) + 1 ))
  chmod 755 "$tmp"
  cp "$tmp/ca.pem" "$tmp/$test_name/private.pem"
  chmod 600 "$tmp/$test_name/private.pem"
  JOOMLA_DB_SSL_CA_FILE="$tmp/$test_name/private.pem"
  expect_failure joomla_prepare_db_encryption
  chmod 644 "$tmp/$test_name/private.pem"
  joomla_prepare_db_encryption
  mkdir "$tmp/$test_name/inaccessible"
  cp "$tmp/ca.pem" "$tmp/$test_name/inaccessible/ca.pem"
  chmod 644 "$tmp/$test_name/inaccessible/ca.pem"
  chmod 700 "$tmp/$test_name/inaccessible"
  JOOMLA_DB_SSL_CA_FILE="$tmp/$test_name/inaccessible/ca.pem"
  expect_failure joomla_prepare_db_encryption
  ln -s "$tmp/$test_name/inaccessible/ca.pem" "$tmp/$test_name/hidden-target.pem"
  JOOMLA_DB_SSL_CA_FILE="$tmp/$test_name/hidden-target.pem"
  expect_failure joomla_prepare_db_encryption
}
test_inline_mutual() {
  JOOMLA_DB_SSL_CA=$(<"$tmp/ca.pem")
  JOOMLA_DB_SSL_CERT=$(<"$tmp/client.pem")
  JOOMLA_DB_SSL_KEY=$(<"$tmp/client.key")
  export JOOMLA_DB_SSL_CERT JOOMLA_DB_SSL_KEY
  joomla_prepare_db_encryption
  [[ $JOOMLA_DB_ENCRYPTION == 2 ]] || fail 'Client credentials must select mode 2'
  assert_argument --db-encryption=2
  assert_argument --db-sslverifyservercert=1
  local kind name path
  for kind in CA CERT KEY; do
    name="JOOMLA_DB_SSL_${kind}_FILE"
    path=${!name}
    [[ $path == "$JOOMLA_DB_SSL_DIR/"* && -s $path ]] || fail "$name was not materialized"
    [[ $(stat -c %a "$path") == 600 ]] || fail "$name permissions are not 0600"
    [[ $(bash -c 'printenv "$1"' bash "$name") == "$path" ]] || fail "$name not exported"
  done
  [[ $(stat -c %a "$JOOMLA_DB_SSL_DIR") == 700 ]] || fail 'TLS directory permissions are not 0700'
  [[ $(<"$JOOMLA_DB_SSL_KEY_FILE") == "$(<"$tmp/client.key")" ]] || fail 'Private key changed'
  assert_argument "--db-sslca=$JOOMLA_DB_SSL_CA_FILE"
  assert_argument "--db-sslcert=$JOOMLA_DB_SSL_CERT_FILE"
  assert_argument "--db-sslkey=$JOOMLA_DB_SSL_KEY_FILE"
}
test_unverified_explicit() {
  JOOMLA_DB_ENCRYPTION=1
  JOOMLA_DB_SSL_VERIFY_SERVER_CERT=0
  joomla_prepare_db_encryption
  assert_argument --db-encryption=1
  assert_argument --db-sslverifyservercert=0
  [[ ${#joomla_db_encryption_args[@]} == 2 ]] || fail 'Unverified mode added certificate arguments'
}
test_postgresql_key_permissions() {
  JOOMLA_DB_TYPE=pgsql
  JOOMLA_DB_SSL_CA=$(<"$tmp/ca.pem")
  JOOMLA_DB_SSL_CERT=$(<"$tmp/client.pem")
  JOOMLA_DB_SSL_KEY=$(<"$tmp/client.key")
  export JOOMLA_DB_SSL_CERT JOOMLA_DB_SSL_KEY
  joomla_prepare_db_encryption
  if [[ $uid == 0 ]]; then
    [[ $(stat -c '%u:%g:%a' "$JOOMLA_DB_SSL_KEY_FILE") == "0:$group:640" ]] || fail 'PostgreSQL key must serve root bootstrap and worker group'
  else
    [[ $(stat -c '%u:%a' "$JOOMLA_DB_SSL_KEY_FILE") == "$uid:600" ]] || fail 'Rootless PostgreSQL key must be private'
  fi
}
test_materialized_retry() {
  JOOMLA_DB_SSL_CA=$(<"$tmp/ca.pem")
  joomla_prepare_db_encryption
  local saved_path=$JOOMLA_DB_SSL_CA_FILE
  unset JOOMLA_DB_SSL_CA_FILE
  JOOMLA_DB_SSL_CA=$(<"$tmp/ca.pem")
  joomla_prepare_db_encryption
  [[ $JOOMLA_DB_SSL_CA_FILE == "$saved_path" ]] || fail 'Retry changed persisted certificate path'
  unset JOOMLA_DB_SSL_CA_FILE
  JOOMLA_DB_SSL_CA=different-certificate
  expect_failure joomla_prepare_db_encryption
  [[ $(<"$saved_path") == "$(<"$tmp/ca.pem")" ]] || fail 'Conflicting input overwrote persisted certificate'
}
test_invalid_inputs() {
  JOOMLA_DB_SSL_CA=certificate
  JOOMLA_DB_SSL_CA_FILE="$tmp/ca.pem"
  expect_failure joomla_prepare_db_encryption
  unset JOOMLA_DB_SSL_CA
  JOOMLA_DB_SSL_CA_FILE=/does/not/exist
  expect_failure joomla_prepare_db_encryption
  unset JOOMLA_DB_SSL_CA_FILE
  JOOMLA_DB_ENCRYPTION=1
  expect_failure joomla_prepare_db_encryption
  JOOMLA_DB_ENCRYPTION=2
  JOOMLA_DB_SSL_CA_FILE="$tmp/ca.pem"
  JOOMLA_DB_SSL_CERT_FILE="$tmp/client.pem"
  expect_failure joomla_prepare_db_encryption
  JOOMLA_DB_SSL_KEY_FILE="$tmp/client.key"
  JOOMLA_DB_ENCRYPTION=1
  expect_failure joomla_prepare_db_encryption
  JOOMLA_DB_ENCRYPTION=2
  JOOMLA_DB_SSL_VERIFY_SERVER_CERT=0
  expect_failure joomla_prepare_db_encryption
  JOOMLA_DB_SSL_VERIFY_SERVER_CERT=invalid
  expect_failure joomla_prepare_db_encryption
  JOOMLA_DB_ENCRYPTION=invalid
  expect_failure joomla_prepare_db_encryption
}
test_unsupported_cipher() {
  JOOMLA_DB_ENCRYPTION=1
  JOOMLA_DB_SSL_CA_FILE="$tmp/ca.pem"
  JOOMLA_DB_SSL_CIPHER=DEFAULT
  expect_failure joomla_prepare_db_encryption
  JOOMLA_DB_ENCRYPTION=2
  JOOMLA_DB_SSL_CERT_FILE="$tmp/client.pem"
  JOOMLA_DB_SSL_KEY_FILE="$tmp/client.key"
  JOOMLA_DB_TYPE=pgsql
  expect_failure joomla_prepare_db_encryption
}
test_unsafe_directory() {
  JOOMLA_DB_SSL_CA=$(<"$tmp/ca.pem")
  JOOMLA_DB_SSL_DIR="$JOOMLA_WEBROOT/tls"
  expect_failure joomla_prepare_db_encryption
  JOOMLA_DB_SSL_DIR=relative/tls
  expect_failure joomla_prepare_db_encryption
}
# These test doubles are called by the sourced entrypoint.
# shellcheck disable=SC2317
test_install_arguments() {
  JOOMLA_SITE_NAME=Test JOOMLA_ADMIN_EMAIL=admin@example.test
  JOOMLA_ADMIN_USERNAME=admin JOOMLA_ADMIN_USER=Administrator
  JOOMLA_ADMIN_PASSWORD=test-password JOOMLA_DB_NAME=joomla
  JOOMLA_DB_PASSWORD=db-password JOOMLA_DB_USER=joomla
  joomla_smtp_args=()
  joomla_post_install() { :; }
  php() {
    printf '%s\n' "$@" >"$tmp/install-arguments"
    printf '<?php\n' >configuration.php
  }
  cd "$JOOMLA_WEBROOT"
  joomla_prepare_db_encryption
  joomla_install
  grep -Fxq -- --db-encryption=0 "$tmp/install-arguments" || fail 'Installer lost default mode'
  if grep -q -- --db-ssl "$tmp/install-arguments"; then fail 'Default installer received SSL arguments'; fi
  JOOMLA_DB_ENCRYPTION=1
  JOOMLA_DB_SSL_CA_FILE="$tmp/ca.pem"
  joomla_prepare_db_encryption
  joomla_install
  grep -Fxq -- --db-encryption=1 "$tmp/install-arguments" || fail 'Installer lost TLS mode'
  grep -Fxq -- "--db-sslca=$tmp/ca.pem" "$tmp/install-arguments" || fail 'Installer lost CA path'
}
# shellcheck disable=SC2317
test_initial_helper_arguments() {
  local expected_mode=0
  joomla_prepare_environment() {
    JOOMLA_DB_USER=joomla JOOMLA_DB_PASSWORD=password JOOMLA_DB_NAME=joomla
  }
  joomla_can_auto_deploy() { return 0; }
  joomla_finalize_webroot() { :; }
  joomla_install() { :; }
  php() {
    [[ $1 == /makedb.php ]] || fail 'Unexpected PHP command'
    if [[ $expected_mode == 0 ]]; then
      [[ $# == 6 ]] || fail 'Default database preparation added TLS argument'
    else
      [[ $# == 7 && $7 == "$expected_mode" ]] || fail 'TLS database preparation lost its mode'
    fi
  }
  cd "$JOOMLA_WEBROOT"
  mkdir -p libraries/src installation
  touch index.php libraries/src/Version.php installation/joomla.php
  joomla_marker="$JOOMLA_WEBROOT/.joomla-initializing"
  joomla_initialize
  expected_mode=1
  JOOMLA_DB_ENCRYPTION=1
  JOOMLA_DB_SSL_CA_FILE="$tmp/ca.pem"
  joomla_initialize
}
# shellcheck disable=SC2317
test_browser_untouched() {
  export JOOMLA_DB_ENCRYPTION=2 JOOMLA_DB_SSL_CA_FILE=/missing
  joomla_prepare_environment() {
    JOOMLA_DB_USER=joomla JOOMLA_DB_PASSWORD=password JOOMLA_DB_NAME=joomla
  }
  joomla_prepare_db_encryption() { fail 'Browser installation prepared TLS'; }
  joomla_finalize_webroot() { :; }
  php() {
    [[ $1 == /makedb.php ]] || fail 'Browser installation invoked installer'
    [[ $# == 6 ]] || fail 'Browser database helper received a TLS mode argument'
  }
  cd "$JOOMLA_WEBROOT"
  mkdir -p libraries/src installation
  touch index.php libraries/src/Version.php installation/joomla.php
  joomla_marker="$JOOMLA_WEBROOT/.joomla-initializing"
  joomla_initialize
  [[ ! -e $JOOMLA_DB_SSL_DIR ]] || fail 'Browser installation created TLS files'
}
# shellcheck disable=SC2317
test_existing_untouched() {
  export JOOMLA_DB_ENCRYPTION=invalid JOOMLA_DB_SSL_CA_FILE=/missing
  mkdir -p "$JOOMLA_WEBROOT/libraries/src" "$tmp/$test_name/bin"
  touch "$JOOMLA_WEBROOT/index.php" "$JOOMLA_WEBROOT/libraries/src/Version.php"
  printf '<?php\n' >"$JOOMLA_WEBROOT/configuration.php"
  printf '#!/bin/sh\nexit 0\n' >"$tmp/$test_name/bin/php-fpm"
  chmod +x "$tmp/$test_name/bin/php-fpm"
  export PATH="$tmp/$test_name/bin:$PATH"
  joomla_prepare_db_encryption() { fail 'Existing installation prepared TLS'; }
  joomla_initialize() { fail 'Existing installation initialized'; }
  joomla_resolve_runtime_identity() { :; }
  joomla_main php-fpm
}

for test_name in default explicit_zero ca_file secret_symlink worker_access inline_mutual unverified_explicit postgresql_key_permissions materialized_retry invalid_inputs \
  unsupported_cipher unsafe_directory install_arguments initial_helper_arguments browser_untouched existing_untouched; do
  ( setup; "test_$test_name" )
  printf 'PASS: %s\n' "$test_name"
done
