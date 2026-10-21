# Documentation

These guides describe the configuration and commands in this checkout. They use
configured values or ask for the release you intend to maintain, so software
version changes do not require rewriting the instructions.

## Choose a task

| I want to… | Read |
| --- | --- |
| Run Joomla, configure its database, or update a container | [Image usage](usage.md) |
| Use Composer, frontend tools or Xdebug | [Development images](development.md) |
| Update software, add PHP support, or add development tools | [Maintenance](maintenance.md) |
| Add or promote alpha, beta, RC or stable releases | [Release tracks](releases.md) |
| Understand a JSON setting or how overrides combine | [Configuration reference](configuration.md) |
| Follow the shell scripts and assess the generation architecture | [Generation walkthrough](generation.md) |
| Run checks or investigate a failed build | [Testing and troubleshooting](testing.md) |
| Submit an image update to Docker Official Images | [Publishing](publishing.md) |

## Repository responsibilities

| Location | What belongs here |
| --- | --- |
| `generate.sh` | The main entry point for preparing image definitions |
| `release.sh` | The publication manifest command |
| `conf/joomla/` | Maintained Joomla series and their release states |
| `conf/php/` | Reusable PHP profiles, variants and development additions |
| `conf/versions-helper.json` | The small index locating the source inputs |
| `conf/archives.json` | Temporary extraction dependencies by archive format |
| `conf/maintainers.json` | Maintainers used in labels and the release manifest |
| `conf/versions.json` | Generated, committed configuration with complete URLs and hashes |
| `src/build/` | The version resolver and Dockerfile generator |
| `src/build/lib/` | Assembly, validation, tag planning and cleanup helpers |
| `src/runtime/` | The entrypoint and database helper edited by contributors |
| `images/` | Generated Dockerfiles and copied runtime files |
| `tests/` | Checks for generators and the resulting containers |
| `.github/workflows/` | Automated checks using the same scripts |

Edit the runtime files under `src/runtime/`, then regenerate. The copies under
`images/` allow each context to build independently. Configured contexts come
from `conf/versions.json`; historical directories that remain in Git do not
implicitly create tags or enter the CI matrix.

The repository generators use Bash, jq and standard command-line utilities.
PHP remains the language of Joomla and the container's database helper. No
Python generator or external template engine is needed.

Return to the [repository overview](../README.md).
