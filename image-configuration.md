# Image configuration

`versions-helper.json` is the human-maintained input. `./update.sh` validates it,
resolves download checksums into `versions.json`, and renders the build contexts.
Only `versions.json` is read during template generation. Commit both the resolved
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
| `apt`, `apk` | Retained distribution packages; only the matching manager is used |
| `build.apt`, `build.apk` | Temporary dependencies, installed alongside `$PHPIZE_DEPS` |
| `extensions.install` | Bundled modules built and enabled by `docker-php-ext-install` |
| `extensions.configure` | Module-to-argument-list map for `docker-php-ext-configure` |
| `extensions.enable` | Already compiled modules enabled by `docker-php-ext-enable` |
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
during the build. `temporary: true` removes a downloaded tool in the same layer.
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

PIE, archives, installer workspaces, caches and temporary build dependencies are
removed in the same `RUN` instruction. Retained libraries are discovered from the
compiled modules using the existing Debian/Alpine cleanup mechanisms.

Literal PHP environment references such as `${JOOMLA_XDEBUG_CLIENT_HOST}` are
preserved in generated configuration. `${DEB_BUILD_MULTIARCH}` is the supported
build-time substitution for bundled extension configure arguments; it is resolved
inside the target Debian image, never on the generator host.

Generation requires Bash, jq and Python 3 (standard library only). The Python
renderer implements installation mechanics; software selections, URLs, versions,
settings, paths and variant choices stay in JSON. Each generated Dockerfile has
one installation `RUN`, with one complete step per continued line. No additional
build script or mounted configuration file is required inside the image.

Run the generator checks with:

```bash
for test in config versions tags manifest templates; do
    ./tests/test-"$test".sh
done
```

CI builds every configured context and runs the runtime checks. The actual
Joomla/database installation check runs only for the stable context owning `latest`.
