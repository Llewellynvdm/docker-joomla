#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "FAIL: template generation at line $LINENO" >&2' ERR
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp "$repo/apply-templates.sh" "$repo/Dockerfile.template" "$repo/"docker-entrypoint*.sh "$repo/makedb.php" "$repo/maintainers.json" "$work/"
cp -r "$repo/scripts" "$work/"
jq --arg fixture current -f "$repo/tests/fixtures.jq" "${TEST_VERSIONS_FILE:-$repo/versions.json}" >"$work/versions.json"
printf 'must not read helper\n' >"$work/versions-helper.json"
cd "$work"
mkdir retired
printf 'preserve\n' >retired/Dockerfile
./apply-templates.sh >/dev/null
python3 - <<'PY'
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
spec = importlib.util.spec_from_file_location('renderer', 'scripts/render-dockerfile.py')
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
config = json.loads(Path('versions.json').read_text())
plan = json.loads(subprocess.check_output(['jq', '-f', 'scripts/tags.jq', 'versions.json']))
for context in plan:
    directory = Path(context['directory'])
    text = (directory / 'Dockerfile').read_text()
    image = config[context['series']]['phpVersions'][context['php']]
    if context['development']:
        image = r.merge(image, image['dev'])
    image = r.merge(image, image['variants'][context['variant']])
    assert 'FROM ' + image['base'] in text, directory
    for item in image['download'].values():
        assert item['package'] in text and item['sha256'] in text, directory
    for name in image.get('pie', {}):
        item = image['sources'][name]
        assert item['package'] in text and item['sha256'] in text, directory
        assert 'docker-php-ext-enable --ini-name ' + item['ini'] + ' ' + item['extension'] in text, directory
    for path, lines in image['config'].items():
        assert path in text, directory
        assert all(line in text for line in lines), directory
    assert text.count('RUN set -eux;') == 1, directory
    for item in image['download'].values():
        if item.get('temporary'):
            assert 'rm -rf ' + item['destination'] in text, directory
    assert 'COPY zz-' not in text, directory
    if not context['development']:
        assert 'xdebug' not in text and 'nodejs' not in text, directory
    # Check the actual shell syntax of every generated RUN instruction.
    logical = text.replace('\\\n', '')
    for line in logical.splitlines():
        if line.startswith('RUN '):
            subprocess.run(['sh', '-n'], input=line[4:], text=True, check=True)
assert Path('retired/Dockerfile').read_text() == 'preserve\n'
# Exercise selections absent from the maintained matrix without assuming versions.
series, settings = next(iter(config.items()))
php, seed = next(iter(settings['phpVersions'].items()))
trial = copy.deepcopy(config)
entry = trial[series]['phpVersions'][php]
entry.setdefault('dev', {})
entry['dev']['apt'] = ['sentinel-dev-package']
entry['dev']['apk'] = ['sentinel-dev-package']
entry['dev']['config'] = {'/tmp/custom.ini': ['custom.value=${RUNTIME_VALUE}']}
variant = settings['variants'][0]
entry['variants'][variant]['base'] = 'php:100.0-test'
normal = r.render(trial, series, next(iter(settings['states'])), php, variant, False, Path('Dockerfile.template').read_text())
dev = r.render(trial, series, next(iter(settings['states'])), php, variant, True, Path('Dockerfile.template').read_text())
assert 'sentinel-dev-package' not in normal and 'sentinel-dev-package' in dev
assert '/tmp/custom.ini' in dev and 'custom.value=${RUNTIME_VALUE}' in dev
assert 'FROM php:100.0-test' in normal
trial[series]['phpVersions']['100.0'] = copy.deepcopy(entry)
del trial[series]['phpVersions']['100.0']['dev']
assert 'sentinel-dev-package' not in r.render(trial, series, next(iter(settings['states'])), '100.0', variant, False, Path('Dockerfile.template').read_text())

PY
find . -name Dockerfile -print0 | sort -z | xargs -0 sha256sum >"$work/before"
./apply-templates.sh >/dev/null
find . -name Dockerfile -print0 | sort -z | xargs -0 sha256sum >"$work/after"
cmp "$work/before" "$work/after"
if ./apply-templates.sh unknown/state >"$work/log" 2>&1; then echo 'Unknown selector accepted' >&2; exit 1; fi
printf '\n@UNKNOWN@\n' >>Dockerfile.template
if ./apply-templates.sh >"$work/log" 2>&1; then echo 'Invalid template accepted' >&2; exit 1; fi
find . -name Dockerfile -print0 | sort -z | xargs -0 sha256sum >"$work/after"
cmp "$work/before" "$work/after"
echo 'Template tests passed.'
