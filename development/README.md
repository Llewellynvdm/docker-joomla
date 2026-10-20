# Joomla development images

The `-dev` variants contain the same Joomla release and PHP/runtime as their
normal counterparts, plus Composer, Xdebug, Git, an SSH client, patch, zip, and
unzip. PHP reports development errors, checks changed files immediately, and
disables JIT. `joomla:dev` follows the development variant of the stable release
selected by `joomla:latest`; it is not a nightly Joomla source build.

Once published, select a versioned tag such as
`joomla:6.2-php8.4-apache-dev`, or use a locally built image. Configure Joomla and
its database as for the normal image. Composer dependencies, PHPUnit, static
analysis tools, and coding standards belong in the project's `composer.json`
and lock file. Node.js/frontend build tools are not included. Nothing runs
`composer install` automatically when the container starts.

## Connect your IDE

Xdebug initiates an outbound connection to the IDE on TCP port **9003**. Do not
publish `9003:9003` on the Joomla service. Apache still serves HTTP and FPM still
uses its usual FastCGI port. Enable the PHP debugger listener in your IDE.

The image uses these environment defaults:

| Variable | Default | Purpose |
| --- | --- | --- |
| `JOOMLA_XDEBUG_CLIENT_HOST` | `host.docker.internal` | Host running the IDE/debug adapter |
| `JOOMLA_XDEBUG_CLIENT_PORT` | `9003` | Port the IDE/debug adapter listens on |
| `XDEBUG_MODE` | `develop,debug` | Enabled Xdebug capabilities |

Docker Desktop provides `host.docker.internal`. On Linux Docker Engine, add
`--add-host=host.docker.internal:host-gateway` to `docker run`, or add the
following to the existing Joomla Compose service:

```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

For a remote Docker host, set `JOOMLA_XDEBUG_CLIENT_HOST` to an IDE address
reachable from that host/container, or use an SSH tunnel. If the debug adapter
runs inside the same development container, use `127.0.0.1`.

Map the container's `/var/www/html` directory to the local Joomla project. In
VS Code, install the PHP Debug extension and use this `.vscode/launch.json`
when the workspace root is the Joomla web root:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Listen for Joomla Xdebug",
      "type": "php",
      "request": "launch",
      "port": 9003,
      "pathMappings": {
        "/var/www/html": "${workspaceFolder}"
      }
    }
  ]
}
```

For PhpStorm, create a PHP server named `joomla`, enable path mappings, and map
the local project to `/var/www/html`. Set `PHP_IDE_CONFIG=serverName=joomla` on
the Joomla service if needed for CLI sessions, and enable **Start Listening for
PHP Debug Connections**. Configure its debugger port as 9003.

Use a browser Xdebug extension or append `?XDEBUG_TRIGGER=1` to a request to
start debugging. For CLI debugging, with a Compose service named `joomla`:

```bash
docker compose exec -e XDEBUG_TRIGGER=1 joomla php cli/joomla.php list
```

Debugging starts only on a trigger. Do not set `XDEBUG_CONFIG` globally: Xdebug
also treats its presence as a legacy debugging trigger. The native ini settings
read the `JOOMLA_XDEBUG_CLIENT_*` variables without that side effect. Official
PHP FPM images preserve environment variables; a custom pool configuration must
also preserve the required variables (normally `clear_env = no`).

Disable Xdebug with `XDEBUG_MODE=off`, or enable coverage for a project test run:

```bash
docker compose exec -e XDEBUG_MODE=coverage joomla vendor/bin/phpunit
```

## Composer and project permissions

Run Composer using the UID/GID that owns your bind-mounted project. Keep its
home/cache writable; do not enable Composer plugins globally as root or disable
Git ownership checks globally. For a disposable Compose run with the project
already mounted and writable by your current user:

```bash
docker compose run --rm --user "$(id -u):$(id -g)" \
  -e COMPOSER_HOME=/tmp/composer-home joomla composer install
```

This creates the Composer home only in that disposable container. For persistent
caching, mount a directory owned by that UID/GID and set `COMPOSER_HOME` to it.
Project and web-server permissions must be aligned with the existing Joomla
image's user configuration.
