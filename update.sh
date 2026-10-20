#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Keep the established helper -> versions -> templates flow. Force refreshes
# package metadata; all generated directories remain under manual management.
targets=()
for argument; do
    case "$argument" in
        -f|--force) ;;
        -h|--help)
            echo 'Usage: ./update.sh [--force] [SERIES | SERIES/STATE ...]'
            exit 0
            ;;
        *) targets+=("$argument") ;;
    esac
done
./versions.sh "$@"
./apply-templates.sh "${targets[@]}"
