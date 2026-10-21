#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

usage() {
    echo 'Usage: ./versions.sh [--force] [SERIES | SERIES/STATE ...]'
}
force=false
targets=()
for argument; do
    case "$argument" in
        -f|--force) force=true ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $argument" >&2; exit 1 ;;
        *) targets+=("${argument%/}") ;;
    esac
done

helper="${VERSIONS_HELPER:-}"
if [ -z "$helper" ]; then
    helper=versions-helper.json
    [ ! -f .versions-helper.json ] || helper=.versions-helper.json
fi
work="$(mktemp -d .versions.XXXXXXXX)"
trap 'rm -rf "$work"' EXIT
jq --arg mode helper -f scripts/validate-config.jq "$helper" > "$work/helper.json"
# Check every expanded tag before making network requests or replacing metadata.
jq -f scripts/tags.jq "$work/helper.json" > /dev/null

mapfile -t releases < <(jq -r 'to_entries[] | .key as $series | .value.states | keys[] | "\($series)/\(.)"' "$work/helper.json")
for target in "${targets[@]}"; do
    jq -e --arg target "$target" '
        ($target | split("/")) as $parts |
        if ($parts | length) == 1 then has($parts[0])
        elif ($parts | length) == 2 then .[$parts[0]].states | has($parts[1])
        else false end
    ' "$work/helper.json" > /dev/null || { echo "Unknown release target: $target" >&2; exit 1; }
done

selected() {
    local release="$1" target
    [ "${#targets[@]}" -gt 0 ] || return 0
    for target in "${targets[@]}"; do
        # Accept either a complete track or a series shared by selected tracks.
        if [ "$target" = "$release" ] || [ "$target" = "${release%%/*}" ] || [ "${target%%/*}" = "$release" ]; then return 0; fi
    done
    return 1
}

# Existing resolved releases provide a cache; legacy versions.json is accepted
# only as a cache during the first migration to the state-based layout.
if [ -f versions.json ]; then jq -e 'type == "object"' versions.json > /dev/null; fi
cp "$work/helper.json" "$work/result.json"
fetch() {
    curl --fail --show-error --silent --location --retry 3 --retry-all-errors --retry-max-time 300 \
        --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' "$@"
}

for release in "${releases[@]}"; do
    series="${release%%/*}"
    state="${release#*/}"
    metadata="$(jq -c --arg series "$series" --arg state "$state" '.[$series].states[$state]' "$work/helper.json")"
    version="$(jq -r '.version' <<< "$metadata")"
    packageType="$(jq -r '.packageType' <<< "$metadata")"
    case "$state" in
        stable) label=Stable ;;
        alpha) label=Alpha ;;
        beta) label=Beta ;;
        rc) label=Release_Candidate ;;
    esac
    asset="Joomla_${version}-${label}-Full_Package.${packageType}"
    officialPackage="https://github.com/joomla/joomla-cms/releases/download/$version/$asset"
    package="$(jq -r --arg default "$officialPackage" '.package // $default' <<< "$metadata")"
    cached='{}'
    if [ -f versions.json ]; then
        cached="$(jq -c --arg series "$series" --arg state "$state" '
            .[$series] as $entry |
            if $entry.states then $entry.states[$state] // {}
            elif $state == "stable" then $entry // {} else {} end
        ' versions.json)"
    fi
    validCache=false
    if jq -e --arg version "$version" --arg package "$package" --arg type "$packageType" '
        .version == $version and .package == $package and .packageType == $type
        and (.sha512 | type == "string" and test("^[a-fA-F0-9]{128}$"))
    ' <<< "$cached" > /dev/null; then validCache=true; fi

    if $validCache && { ! $force || ! selected "$release"; }; then
        sha512="$(jq -r '.sha512 | ascii_downcase' <<< "$cached")"
        echo "Using resolved Joomla $version ($release)" >&2
    else
        if ! selected "$release"; then
            echo "Unresolved or changed release $release; include it or run ./update.sh without selectors." >&2
            exit 1
        fi
        echo "Resolving Joomla $version ($release)" >&2
        digest=
        if [ "$package" = "$officialPackage" ]; then
            # Resolve an exact published full-package asset. GitHub's prerelease
            # flag alone is not a reliable indication of Joomla's release state.
            headers=(-H 'Accept: application/vnd.github+json')
            token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
            if [ -n "$token" ]; then headers+=(-H "Authorization: Bearer $token"); fi
            fetch "${headers[@]}" "https://api.github.com/repos/joomla/joomla-cms/releases/tags/$version" -o "$work/release.json"
            digest="$(jq -r --arg version "$version" --arg asset "$asset" --arg package "$package" '
                if .tag_name != $version or .draft != false then error("unexpected or draft release") else . end |
                [.assets[] | select(.name == $asset and .browser_download_url == $package)] |
                if length != 1 then error("expected exactly one matching full-package asset") else .[0].digest end |
                if . == null then ""
                elif type == "string" and test("^sha256:[a-fA-F0-9]{64}$") then ltrimstr("sha256:")
                else error("invalid published SHA256") end
            ' "$work/release.json")"
        fi
        fetch "$package" -o "$work/package"
        if [ -n "$digest" ]; then
            printf '%s  %s\n' "$digest" "$work/package" | sha256sum --check --status
        fi
        sha512="$(sha512sum "$work/package")"
        sha512="${sha512%% *}"
        rm -f "$work/package"
    fi
    jq --arg series "$series" --arg state "$state" --arg package "$package" --arg sha512 "$sha512" '
        .[$series].states[$state] += {package: $package, sha512: $sha512}
    ' "$work/result.json" > "$work/next.json"
    mv "$work/next.json" "$work/result.json"
done

# Development tools belong to the series, so a state selector refreshes its
# shared tools too. Process selected series first to share a forced download.
selectedSeries=()
otherSeries=()
while IFS= read -r series; do
    if selected "$series"; then selectedSeries+=("$series"); else otherSeries+=("$series"); fi
done < <(jq -r 'to_entries[] | select(.value.development != null) | .key' "$work/helper.json")
declare -A toolHashes=()
for series in "${selectedSeries[@]}" "${otherSeries[@]}"; do
    for tool in composer pie xdebug npm; do
        version="$(jq -r --arg series "$series" --arg tool "$tool" '.[$series].development[$tool].version' "$work/helper.json")"
        case "$tool" in
            composer) package="https://getcomposer.org/download/$version/composer.phar" ;;
            pie) package="https://github.com/php/pie/releases/download/$version/pie.phar" ;;
            xdebug) package="https://github.com/xdebug/xdebug/archive/refs/tags/$version.tar.gz" ;;
            npm) package="https://registry.npmjs.org/npm/-/npm-$version.tgz" ;;
        esac
        key="$tool:$version"
        if [[ ! -v "toolHashes[$key]" ]]; then
            cached=
            if [ -f versions.json ]; then
                # A version alone cannot identify the bytes when a download source changes.
                cached="$(jq -r --arg tool "$tool" --arg version "$version" --arg package "$package" '
                    [.[] | .development[$tool] | select(.version == $version and .package == $package)
                        | .sha256 | select(type == "string" and test("^[a-fA-F0-9]{64}$"))][0] // ""
                ' versions.json)"
            fi
            if [ -n "$cached" ] && { ! $force || ! selected "$series"; }; then
                toolHashes[$key]="${cached,,}"
            else
                if ! selected "$series"; then
                    echo "Unresolved or changed $tool $version for $series; include it or run ./update.sh without selectors." >&2
                    exit 1
                fi
                echo "Resolving $tool $version ($series)" >&2
                fetch "$package" -o "$work/tool"
                checksum="$(sha256sum "$work/tool")"
                toolHashes[$key]="${checksum%% *}"
                if [ "$tool" = composer ]; then
                    fetch "$package.sha256sum" -o "$work/tool.sha256sum"
                    read -r expected filename < "$work/tool.sha256sum" || true
                    [[ "$expected" =~ ^[a-fA-F0-9]{64}$ && "$filename" = composer.phar ]] \
                        || { echo 'Invalid published Composer SHA256' >&2; exit 1; }
                    printf '%s  %s\n' "$expected" "$work/tool" | sha256sum --check --status
                fi
                rm -f "$work/tool"
            fi
        fi
        jq --arg series "$series" --arg tool "$tool" --arg package "$package" --arg sha256 "${toolHashes[$key]}" '
            .[$series].development[$tool] += {package: $package, sha256: $sha256}
        ' "$work/result.json" > "$work/next.json"
        mv "$work/next.json" "$work/result.json"
    done
done

jq --arg mode resolved -S -f scripts/validate-config.jq "$work/result.json" > "$work/versions.json"
mv "$work/versions.json" versions.json
