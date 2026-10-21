#!/usr/bin/env python3
"""Render explicit Docker build steps from resolved image configuration."""
import copy
import json
import re
from pathlib import Path
import shlex
import sys


def merge(left, right):
    result = copy.deepcopy(left)
    for key, value in right.items():
        if key == 'config':
            result[key] = {**result.get(key, {}), **copy.deepcopy(value)}
        elif isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = merge(result[key], value)
        elif isinstance(value, list) and isinstance(result.get(key), list):
            result[key] = list(dict.fromkeys(result[key] + value))
        else:
            result[key] = copy.deepcopy(value)
    return result


def quote(value):
    return shlex.quote(str(value))


def words(values):
    return ' '.join(map(quote, values))


def render(configuration, series, state, php, variant, development, template):
    settings = configuration[series]
    release = settings['states'][state]
    image = copy.deepcopy(settings['phpVersions'][php])
    if development:
        image = merge(image, image['dev'])
    image = merge(image, image['variants'][variant])
    manager = 'apk' if 'alpine' in variant else 'apt'
    steps = []
    if manager == 'apt':
        steps += ['export DEBIAN_FRONTEND=noninteractive', 'apt-get update']
        if image.get('apt'):
            steps.append('apt-get install -y --no-install-recommends ' + words(image['apt']))
        steps.append('savedAptMark="$(apt-mark showmanual)"')
        steps.append('apt-get install -y --no-install-recommends $PHPIZE_DEPS ' + words(image['build']['apt']))
        steps.append('DEB_BUILD_MULTIARCH="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"')
    else:
        if image.get('apk'):
            steps.append('apk add --no-cache ' + words(image['apk']))
        steps.append('apk add --no-cache --virtual .build-deps $PHPIZE_DEPS ' + words(image['build']['apk']))
    for name, options in image['extensions'].get('configure', {}).items():
        args = []
        for value in options:
            # This single documented build fact is resolved inside the target image.
            args.append('"' + value + '"' if '${DEB_BUILD_MULTIARCH}' in value else quote(value))
        steps.append('docker-php-ext-configure ' + quote(name) + ' ' + ' '.join(args))
    if image['extensions'].get('install'):
        steps.append('docker-php-ext-install -j "$(nproc)" ' + words(image['extensions']['install']))
    fetch = "curl --fail --show-error --silent --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https'"
    temporary = []
    for name, item in image.get('download', {}).items():
        target = item['destination'] if item['type'] == 'binary' else '/tmp/download-' + name
        steps += [fetch + ' ' + quote(item['package']) + ' -o ' + quote(target),
                  'echo ' + quote(item['sha256'] + '  ' + target) + ' | sha256sum -c -']
        if item['type'] == 'binary':
            steps.append('chmod 0755 ' + quote(target))
        else:
            steps += ['mkdir -p ' + quote(item['destination']),
                      'tar -xzf ' + quote(target) + ' -C ' + quote(item['destination']) + ' --strip-components=1 --no-same-owner',
                      'rm -f ' + quote(target)]
        for link, source in item.get('links', {}).items():
            steps.append('ln -s ' + quote(source) + ' ' + quote(link))
        if item.get('temporary'):
            temporary.append(item['destination'])
    for installer in ('pie', 'pecl'):
        for name, version in image.get(installer, {}).items():
            if installer == 'pie':
                # PIE resolves the pinned package and enables it through the
                # official PHP image's docker-php-ext-enable helper.
                steps.append('PIE_WORKING_DIRECTORY=/tmp/joomla-pie ' + quote(image['download']['pie']['destination'])
                             + ' install --no-interaction --no-cache --make-parallel-jobs="$(nproc)" '
                             + quote(name + ':' + version))
            else:
                steps.append("printf '\\n' | pecl install " + quote(name + '-' + version))
    if image['extensions'].get('enable'):
        steps.append('docker-php-ext-enable ' + words(image['extensions']['enable']))
    if image.get('npm'):
        packages = [name + '@' + version for name, version in image['npm'].items()]
        steps.append('npm_config_cache=/tmp/joomla-npm npm install --global --prefix /usr/local '
                     '--no-audit --no-fund --engine-strict ' + words(packages))
        steps.append('hash -r')
    steps.append('rm -rf ' + words(temporary + ['/tmp/joomla-pie', '/tmp/joomla-npm', '/tmp/pear', '/root/.cache']))
    archive = '/tmp/joomla.' + release['packageType']
    steps += [fetch + ' ' + quote(release['package']) + ' -o ' + quote(archive),
              'echo ' + quote(release['sha512'] + '  ' + archive) + ' | sha512sum -c -',
              'mkdir -p /usr/src/joomla',
              'tar ' + ('--zstd ' if release['packageType'] == 'tar.zst' else '') + '-xf ' + quote(archive) + ' -C /usr/src/joomla',
              'rm -f ' + quote(archive), 'chown -R www-data:www-data /usr/src/joomla']
    steps.append('extDir="$(php-config --extension-dir)"')
    cleanup = Path(__file__).with_name('cleanup-' + manager + '.inc').read_text()
    # Join wrapped pipelines into one complete shell command per Dockerfile line.
    continuation = chr(92) + '\n'
    cleanup = cleanup.replace('; ' + continuation, ';\n').replace(continuation, ' ')
    steps += [line.strip().rstrip(';') for line in cleanup.splitlines() if line.strip() and not line.lstrip().startswith('#')]
    steps += ['! { ldd "$extDir"/*.so | grep "not found"; }',
              'err="$(php --version 3>&1 1>&2 2>&3)"', '[ -z "$err" ]']
    for path, lines in image.get('config', {}).items():
        steps += ['mkdir -p ' + quote(str(Path(path).parent)),
                  "printf '%s\\n' " + words(lines) + ' > ' + quote(path)]
    if image.get('apache'):
        apache = image['apache']
        steps += ['a2enmod ' + words(apache['modules']), 'a2enconf ' + words(apache['enable'])]
        if apache.get('remoteAddress'):
            steps.append("find /etc/apache2 -type f -name '*.conf' -exec sed -ri 's/([[:space:]]*LogFormat[[:space:]]+\"[^\"]*)%h([^\"]*\")/\\1%a\\2/g' '{}' +")
    replacements = {
        'BASE': image['base'],
        'ENVIRONMENT': '\n'.join('ENV ' + key + '=' + json.dumps(value) for key, value in image['environment'].items()),
        'INSTALL': 'RUN set -eux; \\\n\t' + '; \\\n\t'.join(steps),
        'COMMAND': json.dumps(image['command']),
        'ENTRYPOINT': json.dumps(image['entrypoint']),
        'VOLUME': json.dumps(image['volume']),
        'WORKDIR': image['workdir'],
        'JOOMLA_VERSION': release['version'], 'JOOMLA_SHA512': release['sha512'],
        'JOOMLA_PACKAGE': quote(release['package']), 'PACKAGE_TYPE': release['packageType'],
        'TAR_OPTION': '--zstd ' if release['packageType'] == 'tar.zst' else '',
    }
    maintainers = json.loads(Path('maintainers.json').read_text())
    replacements['MAINTAINERS'] = ', '.join(f"{m['firstname']} {m['lastname']} <{m['email']}> (@{m['github']})" for m in maintainers)
    for key, value in replacements.items():
        template = template.replace('@' + key + '@', value)
    if re.search(r'@[A-Z_]+@', template):
        raise ValueError('Unresolved Dockerfile template token')
    return template


if __name__ == '__main__':
    filename, series, state, php, variant, development, template = sys.argv[1:]
    print(render(json.loads(Path(filename).read_text()), series, state, php, variant,
                 development == '1', Path(template).read_text()), end='')
