# Image configuration

`versions-helper.json` is the human-maintained input. `./update.sh` validates it,
resolves download checksums into `versions.json`, and runs `./build.sh` to generate
the build contexts. Only `versions.json` is read during Dockerfile generation. Commit both the resolved
file and generated contexts after reviewing an update. No hashes belong in the helper.

Each series selects release `states`, PHP versions, runtime variants and tag
aliases. Each `phpVersions` entry describes its normal image. Its optional `dev`
object adds development packages, extensions, tools, settings and environment
values for that PHP version. Development availability has no fixed Joomla version
threshold. The matching `variants` entry selects the PHP base image and command,
and can supply distribution or server-specific settings.

The merge order is PHP settings, `dev` when selected, then the selected variant.
Objects merge by key, lists append with duplicates removed, and scalar values
replace earlier values. Configuration files replace their complete line list at
the same destination. To remove an inherited package, edit its defining list.
There is no implicit package selection based on release numbers.

| Group | Meaning |
| --- | --- |
| Series-level `archives` | Joomla archive formats keyed by `tar.zst`, `tar.gz` or `tar.bz2`, each with temporary `apt` and `apk` extraction dependencies |
| `apt`, `apk` | Retained distribution packages; only the matching manager is used |
| `build.apt`, `build.apk` | Temporary dependencies, installed alongside `$PHPIZE_DEPS` |
| `extensions.install` | Bundled modules built and enabled by `docker-php-ext-install` |
| `extensions.configure` | Module-to-argument-list map for `docker-php-ext-configure` |
| `extensions.enable` | Already compiled modules enabled by `docker-php-ext-enable` |
| `extensions.check` | Additional runtime module names to check, beyond bundled modules in `extensions.install` |
| `checks` | Runtime check commands, each expressed as an array of arguments; development and variant settings can add checks |
| `pie`, `pecl` | Extension package-to-version maps |
| `npm` | Packages and versions installed globally through npm |
| `download` | Tool versions, full artifact URLs, installation type and destination |
| `config` | Absolute destination paths mapped to complete file lines |
| `environment` | Runtime environment defaults |
| `variants` | Explicit base image, runtime command and variant settings |
| `volume`, `workdir`, `entrypoint` | Docker runtime metadata |

Downloads support executable `binary` files and `tar.gz` archives extracted with
one leading directory removed. `links` maps symlink destinations to their targets.
Every direct download receives a checksum in `versions.json` and is verified
during the build: SHA256 for tools and SHA512 for Joomla archives.
`temporary: true` removes a downloaded tool in the same layer.
The configured PIE download must be temporary. An optional `checksum` URL points
to a publisher's SHA256 file; the first whitespace-separated field is verified.

PIE installs the exact configured `package:version` directly and uses Docker's PHP
helper to enable it. APT, APK, PIE, PECL and npm manage their own package downloads;
their packages need no extra source URLs or hashes in this configuration. If a
PECL package is selected, list its module in `extensions.enable`.

Node.js comes from the distribution. Development images install the distribution's
npm temporarily, use it to install the configured npm version under `/usr/local`,
then remove the bootstrap npm and its unneeded dependencies. `--engine-strict`
rejects incompatible Node.js versions. Composer remains a direct PHAR download:
distribution Composer packages depend on a separate distribution PHP installation.

PIE, installer workspaces, caches and temporary extension build dependencies are
removed in the extension installation layer. Runtime `apt`/`apk` packages remain
separate from `build.apt`/`build.apk`, so cleanup preserves requested runtime tools.
Debian cleanup resolves shared-library owners across filesystem aliases while
preserving architecture-qualified package names. Alpine retains the shared
libraries required by the compiled modules. Checks load the modules through PHP
after cleanup; standalone Alpine `ldd` output is not used as a PHP load test.
The generator checks PHP startup diagnostics, then runs `php --ri` for every
module in `extensions.install` and `extensions.check`. Use runtime names in
`extensions.check`, such as `Zend OPcache`, and include modules installed by PIE
or PECL there. An enabled extension's file name can differ from its runtime name.

The selected Joomla archive format supplies temporary extraction dependencies
from the series-level `archives` map. Those packages and the downloaded archive
are removed in the same layer that extracts Joomla.

Literal PHP environment references such as `${JOOMLA_XDEBUG_CLIENT_HOST}` are
preserved in generated configuration. `${DEB_BUILD_MULTIARCH}` is the supported
build-time substitution for bundled extension configure arguments; it is resolved
inside the target Debian image, never on the generator host.

`./build.sh` uses Bash and jq to generate complete Dockerfiles without a template
file or external templating engine. It implements installation mechanics;
software selections, URLs, versions, settings, paths and variant choices stay in
JSON. Each generated Dockerfile has three `RUN` layers:

1. Install PHP extensions and tools, then remove temporary installers and build
   dependencies.
2. Write configuration and run module and command checks after cleanup.
3. Download and extract Joomla, then remove its archive and temporary extraction
   dependencies.

Commands and package lists use readable continuations with separate items on
their own lines. Explicit `COPY --chmod` modes set runtime file permissions.
No additional build script or mounted configuration file is required inside the
image.

Tool download metadata uses build arguments such as `PIE_URL` and `PIE_SHA256`.
Joomla's `ENV` version and SHA512 values and its download URL `ARG` appear only
after extension compilation and configuration. Updating Joomla therefore reuses
those earlier layers when their inputs have not changed. The downloaded bytes
are still checked against the hashes generated in `versions.json`.

Manifest generation retrieves official PHP architecture metadata with `curl` and
parses it with standard shell tools.

Run the generator checks with:

```bash
for test in config versions tags manifest build cleanup; do
    ./tests/test-"$test".sh
done
```

CI builds every configured context and runs the runtime checks. The actual
Joomla/database installation check runs only for the stable context owning `latest`.
