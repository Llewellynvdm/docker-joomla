# Using the images

The image contains a Joomla release, PHP and the selected server variant.
Normal images provide the application runtime. Development images add debugging
and project tools; see [Development images](development.md). The release states
`alpha`, `beta`, `rc` and `stable` identify separate configured tracks.

A tag listed by this checkout is a planned image, not proof that it has been
published. Published official tags are listed on
[Docker Hub](https://hub.docker.com/_/joomla). For changes still under review,
build the generated context locally.

## Choose a context and tag

From the repository root, list the configured contexts:

```bash
jq -r -f src/build/lib/tags.jq conf/versions.json \
  | jq -r '.[] | [.directory, (.tags | join(", "))] | @tsv'
```

The paths identify Joomla series, release state, PHP version and runtime.
A `-dev` suffix on the variant directory selects its development image.
The exact release tag is produced from the configuration. Other aliases follow
only the states and defaults explicitly configured by maintainers.

| Variant | How to serve requests |
| --- | --- |
| `apache` | Includes Apache; publish its HTTP port `80` |
| `fpm` | Runs PHP-FPM on FastCGI port `9000`; provide a separate web server |
| `fpm-alpine` | Runs PHP-FPM using the Alpine-based PHP image; provide a separate web server |

FPM does not serve HTTP directly. Its front-end server must route PHP requests
using the same document-root paths and have access to the Joomla files required
to serve static content. The complete local example below uses Apache.

## Build and run a local Apache image

Run the following in Bash from the repository root. It generates the contexts,
selects a configured stable Apache image and assigns a local tag without
embedding a release number in the instructions:

```bash
./generate.sh
image_context="$(jq -c -f src/build/lib/tags.jq conf/versions.json \
  | jq -ce 'map(select(.state == "stable" and .variant == "apache"
      and (.development | not)))
    | first // error("No stable Apache image is configured")')"
export JOOMLA_IMAGE="joomla-local:$(jq -r '.tags[0]' <<<"$image_context")"
docker build --pull --tag "$JOOMLA_IMAGE" \
  "$(jq -r '.directory' <<<"$image_context")"
```

To use another configured context, copy a directory from the listing and select
it explicitly before running the build:

```bash
read -r -p 'Generated image context directory: ' image_directory
image_context="$(jq -c -f src/build/lib/tags.jq conf/versions.json \
  | jq -ce --arg directory "$image_directory" \
    '.[] | select(.directory == $directory)')"
export JOOMLA_IMAGE="joomla-local:$(jq -r '.tags[0]' <<<"$image_context")"
docker build --pull --tag "$JOOMLA_IMAGE" "$image_directory"
```

For the Apache Compose example, choose a MariaDB image reference supported by
the selected Joomla release and enter a database password. Keep these variables
in the same terminal used to run Compose:

```bash
read -r -p 'MariaDB image reference, including its tag: ' MARIADB_IMAGE
: "${MARIADB_IMAGE:?A MariaDB image reference is required}"
read -r -s -p 'Password for the Joomla database user: ' JOOMLA_DB_PASSWORD
printf '\n'
: "${JOOMLA_DB_PASSWORD:?A database password is required}"
export MARIADB_IMAGE JOOMLA_DB_PASSWORD
```

Create a `compose.yaml` in your deployment directory with this complete content:

```yaml
services:
  database:
    image: ${MARIADB_IMAGE:?Set MARIADB_IMAGE}
    environment:
      MARIADB_RANDOM_ROOT_PASSWORD: "1"
      MARIADB_DATABASE: joomla
      MARIADB_USER: joomla
      MARIADB_PASSWORD: ${JOOMLA_DB_PASSWORD:?Set JOOMLA_DB_PASSWORD}
    volumes:
      - database:/var/lib/mysql
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 5s
      timeout: 5s
      retries: 24
    restart: unless-stopped

  joomla:
    image: ${JOOMLA_IMAGE:?Set JOOMLA_IMAGE}
    pull_policy: never
    ports:
      - "127.0.0.1:8080:80"
    environment:
      JOOMLA_DB_HOST: database
      JOOMLA_DB_NAME: joomla
      JOOMLA_DB_USER: joomla
      JOOMLA_DB_PASSWORD: ${JOOMLA_DB_PASSWORD:?Set JOOMLA_DB_PASSWORD}
    volumes:
      - joomla:/var/www/html
    depends_on:
      database:
        condition: service_healthy
    restart: unless-stopped

volumes:
  database:
  joomla:
```

Start it from the directory containing that file:

```bash
docker compose up -d
docker compose logs -f joomla
```

Open `http://localhost:8080` to complete the Joomla browser installer. Use the
same database host, name, user and password as the Compose configuration. The
HTTP port is bound to the local machine for this development example.

For an already published image, set `JOOMLA_IMAGE` to its published reference,
remove `pull_policy: never`, and pull that tag before recreating the service.
Do not commit deployment credentials to this image-source repository. For a
persistent deployment, supply the same values through your normal Compose
environment or secrets mechanism. Changing a database image's password variable
does not change an existing database user's password in an initialized volume.

## What the entrypoint does

The maintained source is
[`src/runtime/docker-entrypoint.sh`](../src/runtime/docker-entrypoint.sh).
It runs the Joomla startup preparation when the command starts with `apache2`
or is exactly `php-fpm`. Commands such as `php --version` run directly after
entrypoint initialization without copying or installing Joomla.

For a normal server start, it:

1. Reads database settings and, when configured, the password file.
2. Copies the packaged Joomla files from `/usr/src/joomla` into the working
   directory when neither `index.php` nor `libraries/src/Version.php` exists.
3. Runs [`makedb.php`](../src/runtime/makedb.php) to connect to the configured
   database server and ensure the database exists.
4. If the Joomla installer is present and all automatic-installation settings
   pass validation, runs that installer and removes its installation directory.
5. After successful automatic installation, processes extension installation,
   SMTP settings and the configured Joomla CLI commands.
6. Starts the requested Apache or FPM command with `exec`.

The database server is external to the Joomla container. The database account
must have the permissions required by the database helper and Joomla. The
helper currently supports `mysqli` and `pgsql`; the Compose example uses
`mysqli`, which is also the default.

## Runtime environment

| Variable | Behaviour |
| --- | --- |
| `JOOMLA_DB_HOST` | Database hostname, optionally followed by `:port`; required for normal server startup |
| `JOOMLA_DB_NAME` | Database name; defaults to `joomla` |
| `JOOMLA_DB_USER` | Database user; defaults to `root`, but deployments should supply their application user |
| `JOOMLA_DB_PASSWORD` | Database password |
| `JOOMLA_DB_PASSWORD_FILE` | Read the database password from this file when the variable is set and the file exists |
| `JOOMLA_DB_PASSWORD_ALLOW_EMPTY` | Only the value `yes` allows an empty password |
| `JOOMLA_DB_TYPE` | `mysqli` or `pgsql`; defaults to `mysqli` |
| `JOOMLA_DB_PREFIX` | Table prefix for automatic installation; defaults to `joom_` |
| `JOOMLA_SITE_NAME` | Site name for automatic installation; longer than two characters |
| `JOOMLA_ADMIN_USER` | Administrator display name; longer than two characters |
| `JOOMLA_ADMIN_USERNAME` | Administrator login name; nonempty and alphabetic only |
| `JOOMLA_ADMIN_PASSWORD` | Administrator password; longer than twelve characters |
| `JOOMLA_ADMIN_EMAIL` | Administrator email address, validated by the entrypoint |
| `JOOMLA_EXTENSIONS_URLS` | Semicolon-separated extension package URLs, processed after successful automatic installation |
| `JOOMLA_EXTENSIONS_PATHS` | Semicolon-separated extension package paths inside the container, processed after successful automatic installation |
| `JOOMLA_SMTP_HOST` | SMTP hostname, optionally with `:port`, applied after successful automatic installation |
| `JOOMLA_SMTP_HOST_PORT` | SMTP port applied after successful automatic installation |
| `JOOMLA_CLI_COMMANDS` | Single-line, semicolon-separated Joomla CLI commands run after successful automatic installation |

Automatic installation requires all five site/administrator variables. Without
them, Joomla's browser installer remains available. Changing them on an already
installed site does not rename the site, reset the administrator or reinstall
Joomla. The SMTP variables configure host and port only; configure SMTP
credentials and other mail settings through Joomla as needed.

The configured image also supplies `JOOMLA_INSTALLATION_DISABLE_LOCALHOST_CHECK`
as an environment value. This repository's shell entrypoint does not read it;
it is passed through to the Joomla processes in the container. Image metadata
such as `JOOMLA_VERSION` describes the packaged release, not necessarily the
version currently installed in a persistent site volume.

For file-based database credentials, mount a readable secret and set
`JOOMLA_DB_PASSWORD_FILE` to its container path. That variable is supported for
the database password; it is not a general `_FILE` mechanism for every setting.

## Run Joomla CLI commands

For an installed site:

```bash
docker compose exec --user www-data joomla php cli/joomla.php list
```

The automatic-installation hook can be configured as:

```yaml
environment:
  JOOMLA_CLI_COMMANDS: "list; cache:clean"
```

The entrypoint adds `--no-interaction`. It splits commands at semicolons and
arguments at spaces or tabs. It does not evaluate shell code or interpret shell
quoting, pipes, substitutions or redirections. Commands requiring an argument
containing spaces should be run directly with `docker compose exec`, where
normal shell argument quoting is available. A failed configured CLI command
stops startup. The hook runs after a successful automatic installation, not on
every container restart and not for a site that is already installed.

## Files, permissions and image updates

Persist `/var/www/html` and the database separately. Named volumes are suitable
for running a site; bind mounts are useful when editing source from the host.
With a bind mount, align ownership and permissions with the account used by the
web server. Run project commands as the file owner rather than creating
root-owned source or dependency directories. See
[Development images](development.md#project-tools-and-permissions).

To update a locally built image, rebuild its context, keep the existing volumes,
and recreate only the Joomla service:

```bash
docker compose up -d --no-deps --pull never --force-recreate joomla
```

For a published image, choose the required published tag and use
`--pull always` instead. Back up the site files and database before a Joomla or
PHP upgrade, and verify the site's extension compatibility with the selected
runtime.

Replacing a container updates PHP and the tools in its image. It does not
replace Joomla files already present in `/var/www/html`. Upgrade that installed
site using Joomla's supported update process. Conversely, updating Joomla in
the volume does not rebuild the container's PHP runtime. Do not delete volumes
to perform a routine image update.

Use [Maintenance](maintenance.md) when changing what the images contain,
[Testing](testing.md) when validating a build, and
[Development images](development.md) for debugging and project tools.
