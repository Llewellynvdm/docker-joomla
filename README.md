# About this Repo

This is the Git repo of the Docker [official image](https://docs.docker.com/docker-hub/official_repos/) for [joomla](https://registry.hub.docker.com/_/joomla/). See [the Docker Hub page](https://registry.hub.docker.com/_/joomla/) for the full readme on how to use this Docker image and for information regarding contributing and issues.

The full readme is generated over in [docker-library/docs](https://github.com/docker-library/docs), specifically in [docker-library/docs/joomla](https://github.com/docker-library/docs/tree/master/joomla).

See a change merged here that doesn't show up on the Docker Hub yet? Check [the "library/joomla" manifest file in the docker-library/official-images repo](https://github.com/docker-library/official-images/blob/master/library/joomla), especially [PRs with the "library/joomla" label on that repo](https://github.com/docker-library/official-images/labels/library%2Fjoomla). For more information about the official images process, see the [docker-library/official-images readme](https://github.com/docker-library/official-images/blob/master/README.md).

## Maintaining releases

Edit `versions-helper.json`. The existing flow remains:

```text
versions-helper.json -> versions.sh -> versions.json -> apply-templates.sh -> build contexts
```

`versions.json` is the resolved snapshot containing download URLs and SHA512 checksums. Do not maintain it separately. Each series defines its PHP versions, default PHP and runtime, base variants, and the release states to build. The allowed states are `stable`, `alpha`, `beta`, and `rc`; a series does not need a stable release.

For example, the `states` member inside the `6.2` configuration could contain:

```json
"states": {
  "stable": { "version": "6.2.0", "aliases": ["6.2", "6", "latest"] },
  "rc": { "version": "6.2.1-rc1", "aliases": ["6.2-rc"] }
}
```

A separate `6.3` configuration can contain only `alpha`, with version `6.3.0-alpha1`. These numbers illustrate the schema; configure releases that Joomla has actually published. Each series/state selects one release tip. Change its full version to advance it, or add another state to build both simultaneously. The version must match its series and state, including the lowercase numbered suffix for prereleases.

The generator creates these paths for every configured PHP version and base variant:

```text
6.2/stable/php8.4/apache/
6.2/stable/php8.4/apache-dev/
6.2/rc/php8.4/fpm-alpine/
6.2/rc/php8.4/fpm-alpine-dev/
6.3/alpha/php8.4/fpm/
6.3/alpha/php8.4/fpm-dev/
```

Set `development` for a series to generate the corresponding `-dev` variants for **all its configured states**. The helper pins Composer and Xdebug versions and SHA256 checksums; see the existing `6.2` configuration. Development variants are supported for Joomla 6.2 and later. Keep `variants` as the base names `apache`, `fpm`, and `fpm-alpine`; the generator derives `apache-dev`, `fpm-dev`, and `fpm-alpine-dev`. See [development image usage](development/README.md) for Composer, IDE setup, Xdebug triggers, and coverage.

Removing a series or state from the helper removes it from the active build/tag plan. The scripts never delete folders. Remove obsolete directories manually when desired; inactive directories are ignored by CI and manifest generation.

## Tags and aliases

The exact release version is always included. `aliases` adds explicitly named release aliases; an empty array or an omitted `aliases` field is valid. Include the minor alias explicitly, such as `"6.2"`; it is not inferred from the directory name. Prerelease aliases must retain their state, such as `6.2-rc`, `6-rc`, or `rc`, and cannot claim stable aliases or `latest`.

Every release name receives a `-phpX.Y-variant` tag. The configured default PHP **and** default runtime also receive the shorter version, version-runtime, and version-PHP tags, preserving the existing default-selection rules. The special alias `latest` supplies the unversioned aliases. Its owner must be a stable release, and collisions across the complete expanded tag set cause generation to fail before metadata is changed.

For a `6.2.0` stable release that owns `latest`, with default PHP 8.4 and Apache:

| Regular tag | Development tag |
| --- | --- |
| `joomla:latest` | `joomla:dev` |
| `joomla:6.2.0` | `joomla:6.2.0-dev` |
| `joomla:6.2.0-php8.4` | `joomla:6.2.0-php8.4-dev` |
| `joomla:6.2.0-php8.4-apache` | `joomla:6.2.0-php8.4-apache-dev` |
| `joomla:php8.3-apache` | `joomla:php8.3-apache-dev` |
| `joomla:6.2.0-php8.4-fpm-alpine` | `joomla:6.2.0-php8.4-fpm-alpine-dev` |

Prerelease tags use the same rules: for example, `6.2.1-rc1-php8.4-apache-dev`. Stable tags do not contain `-stable`. The `dev` alias is the development counterpart of `latest`; `latest-dev` is not generated.

## Regenerating files

The scripts require Bash, GNU coreutils, GNU awk, jq, curl, and Git. From your working branch, run:

```sh
./update.sh
```

This validates the complete configuration and tag namespace, resolves published Joomla package metadata, updates `versions.json`, and creates or updates every active build context. A matching resolved release is reused from `versions.json`; changing only aliases, PHP settings, or tool pins still regenerates the files. Use force to fetch and verify packages again:

```sh
./update.sh --force
```

Optional selectors restrict package refresh and template generation:

```sh
./update.sh 6.2
./update.sh --force 6.2/rc
```

Unselected releases must already have matching resolved metadata. After a broad configuration change, run without selectors. `./apply-templates.sh` regenerates from the resolved snapshot without fetching Joomla metadata; it accepts the same series or series/state selectors.

The series `packageType` is inherited by its states and can be overridden per state. The resolver requires an exact published full-package asset and verifies the GitHub release asset digest before recording its SHA512. If upstream lacks that digest, supply a verified `sha512` in the helper. A custom HTTPS `package` URL always requires its corresponding `sha512`.

Review `versions.json` and all generated files, build/test the affected images, and commit them with the source changes. Use `git add` so newly created directories are included; `git commit -am` alone misses them. On the initial migration from the old layout, all active paths change to include the state directory.

CI runs generator fixtures, checks deterministic rendering, builds every active context on the hosted runner, and runs the Docker Official Images tests plus Joomla runtime checks. Development image checks exercise Composer as `www-data`, Xdebug modes, and real triggered CLI and Apache/FPM debugging sessions. CI does not publish images. The source-only migration can retain a legacy `versions.json` while CI builds freshly generated contexts; once the snapshot uses `states`, CI also requires active generated outputs to match the committed files. Generated outputs must be committed before submitting an Official Images manifest.

## Preparing the Official Images manifest

After the generated contexts are committed and the branch is pushed, install [bashbrew](https://github.com/docker-library/bashbrew) and run:

```sh
./generate-stackbrew-library.sh > ../official-images/library/joomla
```

The manifest uses the same tag plan as templating and CI, includes only configured states, and derives architectures from each PHP parent. It refuses missing, untracked, or modified build contexts. Every `GitCommit` refers to committed files; generating a manifest does not publish images.

The default `GitRepo` remains the upstream Joomla image repository. To review a manifest against a pushed fork branch, set both overrides explicitly:

```sh
STACKBREW_GIT_REPO=https://github.com/Llewellynvdm/docker-joomla.git \
STACKBREW_GIT_FETCH=refs/heads/feature/prerelease-dev-images \
  ./generate-stackbrew-library.sh > ../official-images/library/joomla
```

Review the tags, directories, commits, and architectures before opening the `docker-library/official-images` pull request. Its review and architecture builds remain required for publication. User-facing changes also belong in [docker-library/docs/joomla](https://github.com/docker-library/docs/tree/master/joomla).
