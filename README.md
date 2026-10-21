# About this Repo

This is the Git repo of the Docker [official image](https://docs.docker.com/docker-hub/official_repos/) for [joomla](https://registry.hub.docker.com/_/joomla/). See [the Docker Hub page](https://registry.hub.docker.com/_/joomla/) for the full readme on how to use this Docker image and for information regarding contributing and issues.

The full readme is generated over in [docker-library/docs](https://github.com/docker-library/docs), specifically in [docker-library/docs/joomla](https://github.com/docker-library/docs/tree/master/joomla).

See a change merged here that doesn't show up on the Docker Hub yet? Check [the "library/joomla" manifest file in the docker-library/official-images repo](https://github.com/docker-library/official-images/blob/master/library/joomla), especially [PRs with the "library/joomla" label on that repo](https://github.com/docker-library/official-images/labels/library%2Fjoomla). For more information about the official images process, see the [docker-library/official-images readme](https://github.com/docker-library/official-images/blob/master/README.md).

---

### Build / Manifest Architecture Support

| Overall Status | Supported Architectures |
|---|---|
| [![All arches status](https://doi-janky.infosiftr.net/job/repo-info/job/local/job/joomla/badge/icon)](https://doi-janky.infosiftr.net/job/repo-info/job/local/job/joomla) | ✅ [amd64](https://hub.docker.com/r/amd64/joomla/) • ✅ [riscv64](https://hub.docker.com/r/riscv64/joomla/) • ✅ [arm32v5](https://hub.docker.com/r/arm32v5/joomla/) • ✅ [arm32v6](https://hub.docker.com/r/arm32v6/joomla/) • ✅ [arm32v7](https://hub.docker.com/r/arm32v7/joomla/) • ✅ [arm64v8](https://hub.docker.com/r/arm64v8/joomla/) • ✅ [i386](https://hub.docker.com/r/i386/joomla/) • ✅ [ppc64le](https://hub.docker.com/r/ppc64le/joomla/) • ✅ [s390x](https://hub.docker.com/r/s390x/joomla/) |

[See OS/ARCH](https://registry.hub.docker.com/_/joomla/?tab=tags) on official images.

---

### Repository checks

| Check | Status |
| --- | --- |
| This branch: image builds and runtime tests | [![Image tests](https://github.com/Llewellynvdm/docker-joomla/actions/workflows/ci.yml/badge.svg?branch=feature%2Fprerelease-dev-images)](https://github.com/Llewellynvdm/docker-joomla/actions/workflows/ci.yml?query=branch%3Afeature%2Fprerelease-dev-images) |
| This branch: generation and shell tests | [![Generation tests](https://github.com/Llewellynvdm/docker-joomla/actions/workflows/verify-build.yml/badge.svg?branch=feature%2Fprerelease-dev-images)](https://github.com/Llewellynvdm/docker-joomla/actions/workflows/verify-build.yml?query=branch%3Afeature%2Fprerelease-dev-images) |

These branch checks validate proposed image definitions. Published tag and
architecture availability is recorded in the Official Images manifest linked
above.

## Use the images

Start with [running and updating containers](docs/usage.md).
Use [development images](docs/development.md) for Composer, frontend tooling
and Xdebug. Alpha, beta and release-candidate tracks keep their prerelease tags;
`latest` belongs to the configured stable release. Availability is controlled by
the release configuration and publication process.

## Update the image definitions

Edit the matching Joomla file in [`conf/joomla/`](conf/joomla/) or PHP profile in
[`conf/php/`](conf/php/), then run from the repository root:

```bash
./generate.sh
```

This resolves download URLs and hashes into [`conf/versions.json`](conf/versions.json)
and regenerates the build contexts under [`images/`](images/).
Review the changes, run the [tests](docs/testing.md), and commit the source
configuration, resolved configuration and generated files together.

A new Joomla series or PHP profile is discovered from its JSON filename.
Routine Joomla release bumps change the state's `version`; its configured URL
pattern supplies the new package URL. See [maintenance](docs/maintenance.md)
and [release tracks](docs/releases.md) for the complete steps.

## Prepare an Official Images release

After the image changes have passed CI and been committed and pushed to the
repository used by the manifest, with an `official-images` checkout alongside:

```bash
./release.sh > ../official-images/library/joomla
```

Review and submit that manifest through the Official Images pull-request
process. This command writes the manifest; it does not push container images.
See [publishing](docs/publishing.md) for the short release procedure, fork
settings and publication checks.

## Find your way around

| Location | Purpose |
| --- | --- |
| [`generate.sh`](generate.sh) | Resolve configuration and generate build contexts |
| [`release.sh`](release.sh) | Generate the Official Images publication manifest |
| [`conf/`](conf/) | Version inputs, PHP profiles and resolved build configuration |
| [`src/build/`](src/build/) | Bash generators and jq helpers |
| [`src/runtime/`](src/runtime/) | Authoritative files copied into the containers |
| [`images/`](images/) | Committed, self-contained Docker build contexts |
| [`tests/`](tests/) | Generator, cleanup and container tests |
| [`docs/`](docs/README.md) | Maintenance, usage and architecture guides |

Read [how generation works](docs/generation.md) for diagrams and a guided
walkthrough of `generate.sh`, `versions.sh` and `build.sh`, written for
contributors who are more familiar with PHP than shell scripting.

Maintainer details are in [`conf/maintainers.json`](conf/maintainers.json).
For the upstream publication process, see the
[Official Images guide](https://github.com/docker-library/official-images/blob/master/README.md)
and [Joomla publication requests](https://github.com/docker-library/official-images/labels/library%2Fjoomla).
