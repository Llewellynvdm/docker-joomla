# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh". DO NOT EDIT.
FROM php:8.4-apache
LABEL maintainer="Llewellyn van der Merwe <llewellyn.van-der-merwe@community.joomla.org> (@Llewellynvdm), Harald Leithner <harald.leithner@community.joomla.org> (@HLeithner)"

ENV JOOMLA_INSTALLATION_DISABLE_LOCALHOST_CHECK="1"
ENV JOOMLA_XDEBUG_CLIENT_HOST="host.docker.internal"
ENV JOOMLA_XDEBUG_CLIENT_PORT="9003"
ENV XDEBUG_MODE="develop,debug"

ENV JOOMLA_VERSION=6.2.0
ENV JOOMLA_SHA512=5d61beed1b2ced52ee96b312d327e8f3616cdd93e5d4a759bef9bc0cee384232a21e3b85e15f659edcdb83fb5ea9969cd009722eeb6151303cc5e6c9d6dc26bc

RUN set -eux; \
	export DEBIAN_FRONTEND=noninteractive; \
	apt-get update; \
	apt-get install -y --no-install-recommends ghostscript git openssh-client patch unzip zip nodejs python3 make g++ jq rsync less nano; \
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get install -y --no-install-recommends $PHPIZE_DEPS libbz2-dev libgmp-dev libicu-dev libfreetype6-dev libjpeg-dev libldap2-dev libmemcached-dev libmagickwand-dev libpq-dev libpng-dev libwebp-dev libzip-dev automake libtool zlib1g-dev unzip zstd; \
	DEB_BUILD_MULTIARCH="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
	docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
	docker-php-ext-configure ldap "--with-libdir=lib/${DEB_BUILD_MULTIARCH}"; \
	docker-php-ext-install -j "$(nproc)" bz2 bcmath exif gd gmp intl ldap mysqli pdo_mysql pdo_pgsql pgsql zip pcntl sockets; \
	docker-php-ext-enable opcache; \
	curl --fail --show-error --silent --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' https://github.com/php/pie/releases/download/1.5.2/pie.phar -o /tmp/pie; \
	echo 'fe70c59738cf56ec00a818cf9cb9593da171aac86f5f1f859995b8839dfd2cc7  /tmp/pie' | sha256sum -c -; \
	chmod 0755 /tmp/pie; \
	curl --fail --show-error --silent --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' https://getcomposer.org/download/2.10.3/composer.phar -o /usr/local/bin/composer; \
	echo '7a2d379d5b8ffdaa028580ef26494c36d2feef4b178d3dd1473a4dbc5e17c8d6  /usr/local/bin/composer' | sha256sum -c -; \
	chmod 0755 /usr/local/bin/composer; \
	curl --fail --show-error --silent --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' https://registry.npmjs.org/npm/-/npm-11.21.1.tgz -o /tmp/download-npm; \
	echo 'dd77c48eb845f4856c2cdba347cfb52bd877a2655a1ea48ff0c4796e3df9dd7b  /tmp/download-npm' | sha256sum -c -; \
	mkdir -p /usr/local/lib/node_modules/npm; \
	tar -xzf /tmp/download-npm -C /usr/local/lib/node_modules/npm --strip-components=1 --no-same-owner; \
	rm -f /tmp/download-npm; \
	node -e 'const path = "/usr/local/lib/node_modules/npm"; const pkg = require(path + "/package.json"); const semver = require(path + "/node_modules/semver"); if (!semver.satisfies(process.version, pkg.engines.node)) { throw new Error("Incompatible Node.js: " + process.version + " requires " + pkg.engines.node); }'; \
	ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm; \
	ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx; \
	curl --fail --show-error --silent --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' https://github.com/krakjoe/apcu/archive/refs/tags/v5.1.28.tar.gz -o /tmp/extension-apcu.tgz; \
	echo '0e60ba9d0fa4021c57a70c071f3d8f71de236275d084e560d5959fec4edd8c32  /tmp/extension-apcu.tgz' | sha256sum -c -; \
	mkdir -p /tmp/extension-apcu; \
	tar -xzf /tmp/extension-apcu.tgz -C /tmp/extension-apcu --strip-components=1 --no-same-owner; \
	PIE_WORKING_DIRECTORY=/tmp/joomla-pie /tmp/pie install --no-interaction --no-cache --working-dir=/tmp/extension-apcu --skip-enable-extension --make-parallel-jobs="$(nproc)"; \
	docker-php-ext-enable --ini-name docker-php-ext-apcu.ini apcu; \
	php -r 'exit(phpversion("apcu") === "5.1.28" ? 0 : 1);'; \
	rm -rf /tmp/extension-apcu /tmp/extension-apcu.tgz; \
	curl --fail --show-error --silent --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' https://github.com/Imagick/imagick/archive/refs/tags/3.8.1.tar.gz -o /tmp/extension-imagick.tgz; \
	echo 'b0e9279ddf6e75a8c6b4068e16daec0475427dbca7ce2e144e30a51a88aa5ddc  /tmp/extension-imagick.tgz' | sha256sum -c -; \
	mkdir -p /tmp/extension-imagick; \
	tar -xzf /tmp/extension-imagick.tgz -C /tmp/extension-imagick --strip-components=1 --no-same-owner; \
	PIE_WORKING_DIRECTORY=/tmp/joomla-pie /tmp/pie install --no-interaction --no-cache --working-dir=/tmp/extension-imagick --skip-enable-extension --make-parallel-jobs="$(nproc)"; \
	docker-php-ext-enable --ini-name docker-php-ext-imagick.ini imagick; \
	php -r 'exit(phpversion("imagick") === "3.8.1" ? 0 : 1);'; \
	rm -rf /tmp/extension-imagick /tmp/extension-imagick.tgz; \
	curl --fail --show-error --silent --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' https://github.com/php-memcached-dev/php-memcached/archive/refs/tags/v3.4.0.tar.gz -o /tmp/extension-memcached.tgz; \
	echo '10b98a0fdc3ce9ab823db59e8935f068de87e374728871a1efacdadd8c7807d1  /tmp/extension-memcached.tgz' | sha256sum -c -; \
	mkdir -p /tmp/extension-memcached; \
	tar -xzf /tmp/extension-memcached.tgz -C /tmp/extension-memcached --strip-components=1 --no-same-owner; \
	PIE_WORKING_DIRECTORY=/tmp/joomla-pie /tmp/pie install --no-interaction --no-cache --working-dir=/tmp/extension-memcached --skip-enable-extension --make-parallel-jobs="$(nproc)"; \
	docker-php-ext-enable --ini-name docker-php-ext-memcached.ini memcached; \
	php -r 'exit(phpversion("memcached") === "3.4.0" ? 0 : 1);'; \
	rm -rf /tmp/extension-memcached /tmp/extension-memcached.tgz; \
	curl --fail --show-error --silent --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' https://github.com/phpredis/phpredis/archive/refs/tags/6.3.0.tar.gz -o /tmp/extension-redis.tgz; \
	echo 'cb8f81df1a275599e4f8ddcfec7e1f65ed1953e6f5673649149fd680ebff4cad  /tmp/extension-redis.tgz' | sha256sum -c -; \
	mkdir -p /tmp/extension-redis; \
	tar -xzf /tmp/extension-redis.tgz -C /tmp/extension-redis --strip-components=1 --no-same-owner; \
	PIE_WORKING_DIRECTORY=/tmp/joomla-pie /tmp/pie install --no-interaction --no-cache --working-dir=/tmp/extension-redis --skip-enable-extension --make-parallel-jobs="$(nproc)"; \
	docker-php-ext-enable --ini-name docker-php-ext-redis.ini redis; \
	php -r 'exit(phpversion("redis") === "6.3.0" ? 0 : 1);'; \
	rm -rf /tmp/extension-redis /tmp/extension-redis.tgz; \
	curl --fail --show-error --silent --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' https://github.com/xdebug/xdebug/archive/refs/tags/3.5.3.tar.gz -o /tmp/extension-xdebug.tgz; \
	echo '954e56021668121ecc50b92d2ad1ce945f22ecf81ffc5bb5835219485b12ef5f  /tmp/extension-xdebug.tgz' | sha256sum -c -; \
	mkdir -p /tmp/extension-xdebug; \
	tar -xzf /tmp/extension-xdebug.tgz -C /tmp/extension-xdebug --strip-components=1 --no-same-owner; \
	PIE_WORKING_DIRECTORY=/tmp/joomla-pie /tmp/pie install --no-interaction --no-cache --working-dir=/tmp/extension-xdebug --skip-enable-extension --make-parallel-jobs="$(nproc)"; \
	docker-php-ext-enable --ini-name zz-xdebug.ini xdebug; \
	php -r 'exit(phpversion("xdebug") === "3.5.3" ? 0 : 1);'; \
	rm -rf /tmp/extension-xdebug /tmp/extension-xdebug.tgz; \
	rm -rf /tmp/pie /tmp/joomla-pie /tmp/pear /root/.cache; \
	curl --fail --show-error --silent --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' https://github.com/joomla/joomla-cms/releases/download/6.2.0/Joomla_6.2.0-Stable-Full_Package.tar.zst -o /tmp/joomla.tar.zst; \
	echo '5d61beed1b2ced52ee96b312d327e8f3616cdd93e5d4a759bef9bc0cee384232a21e3b85e15f659edcdb83fb5ea9969cd009722eeb6151303cc5e6c9d6dc26bc  /tmp/joomla.tar.zst' | sha512sum -c -; \
	mkdir -p /usr/src/joomla; \
	tar --zstd -xf /tmp/joomla.tar.zst -C /usr/src/joomla; \
	rm -f /tmp/joomla.tar.zst; \
	chown -R www-data:www-data /usr/src/joomla; \
	extDir="$(php-config --extension-dir)"; \
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	ldd "$extDir"/*.so  		| awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); print so }'  		| sort -u  		| xargs -r dpkg-query --search  		| cut -d: -f1  		| sort -u  		| xargs -rt apt-mark manual; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*; \
	! { ldd "$extDir"/*.so | grep "not found"; }; \
	err="$(php --version 3>&1 1>&2 2>&3)"; \
	[ -z "$err" ]; \
	mkdir -p /usr/local/etc/php/conf.d; \
	printf '%s\n' 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR' 'display_errors = Off' 'display_startup_errors = Off' 'log_errors = On' 'error_log = /dev/stderr' 'log_errors_max_len = 1024' 'ignore_repeated_errors = On' 'ignore_repeated_source = Off' 'html_errors = Off' > /usr/local/etc/php/conf.d/error-logging.ini; \
	mkdir -p /usr/local/etc/php/conf.d; \
	printf '%s\n' opcache.memory_consumption=128 opcache.interned_strings_buffer=8 opcache.max_accelerated_files=4000 opcache.revalidate_freq=2 > /usr/local/etc/php/conf.d/opcache-recommended.ini; \
	mkdir -p /usr/local/etc/php/conf.d; \
	printf '%s\n' 'error_reporting = E_ALL' 'display_errors = On' 'display_startup_errors = On' 'log_errors = On' 'ignore_repeated_errors = Off' 'opcache.validate_timestamps = 1' 'opcache.revalidate_freq = 0' 'opcache.jit = off' 'opcache.jit_buffer_size = 0' > /usr/local/etc/php/conf.d/zz-joomla-development.ini; \
	mkdir -p /usr/local/etc/php/conf.d; \
	printf '%s\n' 'xdebug.mode = develop,debug' 'xdebug.start_with_request = trigger' 'xdebug.start_upon_error = no' 'xdebug.discover_client_host = 0' 'xdebug.client_host = ${JOOMLA_XDEBUG_CLIENT_HOST}' 'xdebug.client_port = ${JOOMLA_XDEBUG_CLIENT_PORT}' 'xdebug.output_dir = /tmp' > /usr/local/etc/php/conf.d/zz-xdebug-settings.ini; \
	mkdir -p /etc/apache2/conf-available; \
	printf '%s\n' 'RemoteIPHeader X-Forwarded-For' 'RemoteIPInternalProxy 10.0.0.0/8' 'RemoteIPInternalProxy 172.16.0.0/12' 'RemoteIPInternalProxy 192.168.0.0/16' 'RemoteIPInternalProxy 169.254.0.0/16' 'RemoteIPInternalProxy 127.0.0.0/8' > /etc/apache2/conf-available/remoteip.conf; \
	a2enmod rewrite expires remoteip; \
	a2enconf remoteip; \
	find /etc/apache2 -type f -name '*.conf' -exec sed -ri 's/([[:space:]]*LogFormat[[:space:]]+"[^"]*)%h([^"]*")/\1%a\2/g' '{}' +

VOLUME ["/var/www/html"]
WORKDIR /var/www/html
COPY docker-entrypoint.sh /entrypoint.sh
COPY makedb.php /makedb.php
ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]
