#!/usr/bin/env bash
# Verify real TLS handshakes and unattended installation on the latest context.
# Usage: tests/test-database-tls.sh IMAGE
set -Eeuo pipefail

image=${1:?image is required}
tmp=$(mktemp -d)
network="joomla-tls-$$-$RANDOM"
database="$network-db"
plain="$network-plain"
postgres="$network-postgres"
web="$network-web"
site_volume="$network-site"
tls_volume="$network-certificates"
pg_server_volume="$network-pg-server"
pg_client_volume="$network-pg-client"
phase='creating test certificates'
trap 'echo >&2 "Database TLS test failed while $phase (line $LINENO)"' ERR
cleanup() {
  local status=$?
  if (( status != 0 )); then
    docker logs "$database" >&2 2>/dev/null || true
    docker logs "$postgres" >&2 2>/dev/null || true
    docker logs "$web" >&2 2>/dev/null || true
    if [[ -f "$tmp/helper.log" ]]; then cat "$tmp/helper.log" >&2; fi
  fi
  docker rm -fv "$web" "$database" "$plain" "$postgres" >/dev/null 2>&1 || true
  docker volume rm "$site_volume" "$tls_volume" "$pg_server_volume" "$pg_client_volume" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  rm -rf -- "$tmp"
}
trap cleanup EXIT

mkdir "$tmp/pki" "$tmp/init" "$tmp/pg-init"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=Joomla-test-CA \
  -keyout "$tmp/ca.key" -out "$tmp/pki/ca.pem" >/dev/null 2>&1
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=Untrusted-test-CA \
  -keyout "$tmp/wrong-ca.key" -out "$tmp/pki/wrong-ca.pem" >/dev/null 2>&1
for certificate in server client; do
  openssl req -new -newkey rsa:2048 -nodes -subj "/CN=$certificate" \
    -keyout "$tmp/pki/$certificate.key" -out "$tmp/$certificate.csr" >/dev/null 2>&1
  if [[ $certificate == server ]]; then
    printf 'subjectAltName=DNS:db,DNS:pgdb\nextendedKeyUsage=serverAuth\n' >"$tmp/extensions"
  else
    printf 'extendedKeyUsage=clientAuth\n' >"$tmp/extensions"
  fi
  openssl x509 -req -days 1 -in "$tmp/$certificate.csr" \
    -CA "$tmp/pki/ca.pem" -CAkey "$tmp/ca.key" -CAcreateserial \
    -extfile "$tmp/extensions" -out "$tmp/pki/$certificate.pem" >/dev/null 2>&1
done
# Disposable test keys must be readable by each container's different worker UID.
chmod 755 "$tmp" "$tmp/pki" "$tmp/init" "$tmp/pg-init"
chmod 644 "$tmp/pki/"*
cat >"$tmp/init/tls.sql" <<'SQL'
ALTER USER 'joomla'@'%' REQUIRE SSL;
CREATE USER 'clientcert'@'%' IDENTIFIED BY 'joomla-test-password' REQUIRE X509;
GRANT ALL ON joomla.* TO 'clientcert'@'%';
SQL

phase='starting TLS and non-TLS databases'
docker network create "$network" >/dev/null
docker run -d --name "$database" --network "$network" --network-alias db --network-alias wrong-name \
  --mount "type=bind,src=$tmp/pki,dst=/tls,readonly" \
  --mount "type=bind,src=$tmp/init,dst=/docker-entrypoint-initdb.d,readonly" \
  -e MARIADB_RANDOM_ROOT_PASSWORD=1 -e MARIADB_DATABASE=joomla \
  -e MARIADB_USER=joomla -e MARIADB_PASSWORD=joomla-test-password \
  mariadb:lts --ssl-ca=/tls/ca.pem --ssl-cert=/tls/server.pem --ssl-key=/tls/server.key \
  --require-secure-transport=ON >/dev/null
docker run -d --name "$plain" --network "$network" --network-alias plain \
  -e MARIADB_RANDOM_ROOT_PASSWORD=1 -e MARIADB_DATABASE=joomla \
  -e MARIADB_USER=joomla -e MARIADB_PASSWORD=joomla-test-password \
  mariadb:lts --skip-ssl >/dev/null
for container in "$database" "$plain"; do
  deadline=$((SECONDS + 120))
  until timeout 5 docker exec "$container" healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1; do
    [[ $(docker inspect --format '{{.State.Running}}' "$container") == true ]]
    if (( SECONDS >= deadline )); then echo >&2 'Database did not become ready'; exit 1; fi
    sleep 2
  done
done

helper() {
  local host=$1 account=$2 mode=$3 ca=$4
  shift 4
  timeout 60 docker run --rm --network "$network" --entrypoint php \
    --mount "type=bind,src=$tmp/pki,dst=/tls,readonly" \
    -e "JOOMLA_DB_SSL_CA_FILE=$ca" -e JOOMLA_DB_SSL_VERIFY_SERVER_CERT=1 \
    "$@" "$image" /makedb.php "$host" "$account" joomla-test-password joomla mysqli "$mode"
}
expect_failure() {
  local status=0
  "$@" >"$tmp/helper.log" 2>&1 || status=$?
  if (( status == 0 || status == 124 )); then
    echo >&2 "Expected a connection failure, received exit $status"
    exit 1
  fi
}

phase='checking verified TLS and mutual TLS'
helper db joomla 1 /tls/ca.pem
helper db clientcert 2 /tls/ca.pem \
  -e JOOMLA_DB_SSL_CERT_FILE=/tls/client.pem -e JOOMLA_DB_SSL_KEY_FILE=/tls/client.key
phase='rejecting an untrusted CA'
expect_failure helper db joomla 1 /tls/wrong-ca.pem
phase='rejecting a mismatched server hostname'
expect_failure helper wrong-name joomla 1 /tls/ca.pem
phase='rejecting a server without TLS'
expect_failure helper plain joomla 1 /tls/ca.pem
phase='enforcing the client-certificate requirement'
expect_failure helper db clientcert 1 /tls/ca.pem
phase='rejecting plaintext on the protected account'
expect_failure docker exec "$database" mariadb --protocol=TCP --skip-ssl \
  -h 127.0.0.1 -u joomla -pjoomla-test-password -e 'SELECT 1'

phase='preparing PostgreSQL TLS permissions and account policy'
docker volume create "$pg_server_volume" >/dev/null
docker volume create "$pg_client_volume" >/dev/null
docker run --rm --user 0 --entrypoint sh \
  --mount "type=bind,src=$tmp/pki,dst=/source,readonly" \
  --mount "type=volume,src=$pg_server_volume,dst=/tls" postgres:latest -ec '
    cp /source/ca.pem /source/server.pem /source/server.key /tls/
    chown postgres:postgres /tls/server.key
    chmod 0600 /tls/server.key
  '
worker_group=$(docker run --rm --entrypoint id "$image" -g www-data)
docker run --rm --user 0 --entrypoint sh \
  --mount "type=bind,src=$tmp/pki,dst=/source,readonly" \
  --mount "type=volume,src=$pg_client_volume,dst=/tls" "$image" -ec '
    cp /source/ca.pem /source/wrong-ca.pem /source/client.pem /source/client.key /tls/
    chown "0:$1" /tls/client.key
    chmod 0640 /tls/client.key
  ' sh "$worker_group"
cat >"$tmp/pg-init/client.sql" <<'SQL'
CREATE USER clientcert WITH CREATEDB PASSWORD 'joomla-test-password';
SQL
cat >"$tmp/pg-hba.conf" <<'CONF'
local all all trust
hostssl all clientcert all scram-sha-256 clientcert=verify-ca
hostssl all joomla all scram-sha-256
host all all all reject
CONF
docker run -d --name "$postgres" --network "$network" --network-alias pgdb \
  --mount "type=volume,src=$pg_server_volume,dst=/tls,readonly" \
  --mount "type=bind,src=$tmp/pg-init,dst=/docker-entrypoint-initdb.d,readonly" \
  --mount "type=bind,src=$tmp/pg-hba.conf,dst=/etc/postgresql/test-pg-hba.conf,readonly" \
  -e POSTGRES_USER=joomla -e POSTGRES_PASSWORD=joomla-test-password \
  postgres:latest -c ssl=on -c ssl_ca_file=/tls/ca.pem -c ssl_cert_file=/tls/server.pem \
  -c ssl_key_file=/tls/server.key -c hba_file=/etc/postgresql/test-pg-hba.conf >/dev/null
deadline=$((SECONDS + 120))
until timeout 5 docker exec "$postgres" pg_isready -U joomla >/dev/null 2>&1; do
  [[ $(docker inspect --format '{{.State.Running}}' "$postgres") == true ]]
  if (( SECONDS >= deadline )); then echo >&2 'PostgreSQL did not become ready'; exit 1; fi
  sleep 2
done
pg_helper() {
  local account=$1 mode=$2 ca=$3
  shift 3
  timeout 60 docker run --rm --network "$network" --entrypoint php \
    --mount "type=volume,src=$pg_client_volume,dst=/tls,readonly" \
    -e "JOOMLA_DB_SSL_CA_FILE=$ca" -e JOOMLA_DB_SSL_VERIFY_SERVER_CERT=1 \
    "$@" "$image" /makedb.php pgdb "$account" joomla-test-password joomla pgsql "$mode"
}
phase='checking PostgreSQL verified TLS and mutual TLS as root and worker'
pg_helper joomla 1 /tls/ca.pem
pg_helper clientcert 2 /tls/ca.pem \
  -e JOOMLA_DB_SSL_CERT_FILE=/tls/client.pem -e JOOMLA_DB_SSL_KEY_FILE=/tls/client.key
pg_helper clientcert 2 /tls/ca.pem --user www-data \
  -e JOOMLA_DB_SSL_CERT_FILE=/tls/client.pem -e JOOMLA_DB_SSL_KEY_FILE=/tls/client.key
phase='rejecting PostgreSQL untrusted CA and missing client certificate'
expect_failure pg_helper joomla 1 /tls/wrong-ca.pem
expect_failure pg_helper clientcert 1 /tls/ca.pem

phase='installing Joomla with inline mutual-TLS secrets'
docker volume create "$site_volume" >/dev/null
docker volume create "$tls_volume" >/dev/null
docker run -d --name "$web" --network "$network" \
  --mount "type=volume,src=$site_volume,dst=/var/www/html" \
  --mount "type=volume,src=$tls_volume,dst=/var/www/joomla-db-tls" \
  -e JOOMLA_DB_HOST=db -e JOOMLA_DB_NAME=joomla -e JOOMLA_DB_USER=clientcert \
  -e JOOMLA_DB_PASSWORD=joomla-test-password -e JOOMLA_DB_ENCRYPTION=2 \
  -e "JOOMLA_DB_SSL_CA=$(<"$tmp/pki/ca.pem")" \
  -e "JOOMLA_DB_SSL_CERT=$(<"$tmp/pki/client.pem")" \
  -e "JOOMLA_DB_SSL_KEY=$(<"$tmp/pki/client.key")" \
  -e JOOMLA_SITE_NAME='Joomla TLS test' -e JOOMLA_ADMIN_USER='Image Test Administrator' \
  -e JOOMLA_ADMIN_USERNAME=imageadmin -e JOOMLA_ADMIN_PASSWORD=joomla-test-admin-password \
  -e JOOMLA_ADMIN_EMAIL=admin@example.test "$image" >/dev/null
deadline=$((SECONDS + 120))
until docker exec "$web" sh -ec 'test -s configuration.php && test ! -d installation && test ! -d .joomla-initializing' >/dev/null 2>&1; do
  [[ $(docker inspect --format '{{.State.Running}}' "$web") == true ]]
  if (( SECONDS >= deadline )); then echo >&2 'TLS installation did not complete'; exit 1; fi
  sleep 2
done
docker exec --user www-data "$web" php -r '
require "configuration.php";
$config = new JConfig;
if ((int) $config->dbencryption !== 2 || !$config->dbsslverifyservercert) { exit(1); }
foreach (["dbsslca", "dbsslcert", "dbsslkey"] as $field) {
    if (!is_readable($config->$field)) { exit(1); }
}
'
docker exec --user www-data "$web" php cli/joomla.php --no-interaction user:list >"$tmp/users"
grep -Fq imageadmin "$tmp/users"

phase='recreating the installed site without reapplying TLS environment settings'
docker rm -f "$web" >/dev/null
docker run -d --name "$web" --network "$network" \
  --mount "type=volume,src=$site_volume,dst=/var/www/html" \
  --mount "type=volume,src=$tls_volume,dst=/var/www/joomla-db-tls" \
  -e JOOMLA_DB_ENCRYPTION=invalid -e JOOMLA_DB_SSL_CA_FILE=/does/not/exist \
  "$image" >/dev/null
docker exec --user www-data "$web" php cli/joomla.php --no-interaction user:list >"$tmp/users"
grep -Fq imageadmin "$tmp/users"
echo "Database TLS and initial deployment checks passed: $image"
