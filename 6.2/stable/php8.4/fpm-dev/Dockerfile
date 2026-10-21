# NOTE: THIS DOCKERFILE IS GENERATED VIA "build.sh". DO NOT EDIT.
FROM php:8.4-fpm
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
	apt-get install -y --no-install-recommends $PHPIZE_DEPS libbz2-dev libgmp-dev libicu-dev libfreetype6-dev libjpeg-dev libldap2-dev libmemcached-dev libmagickwand-dev libpq-dev libpng-dev libwebp-dev libzip-dev automake libtool zlib1g-dev unzip zstd npm; \
	DEB_BUILD_MULTIARCH="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
	docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
	docker-php-ext-configure ldap --with-libdir=lib/"${DEB_BUILD_MULTIARCH}"; \
	docker-php-ext-install -j "$(nproc)" bz2 bcmath exif gd gmp intl ldap mysqli pdo_mysql pdo_pgsql pgsql zip pcntl sockets; \
	curl --fail --show-error --silent --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' https://github.com/php/pie/releases/download/1.5.2/pie.phar -o /tmp/pie; \
	echo 'fe70c59738cf56ec00a818cf9cb9593da171aac86f5f1f859995b8839dfd2cc7  /tmp/pie' | sha256sum -c -; \
	chmod 0755 /tmp/pie; \
	curl --fail --show-error --silent --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' https://getcomposer.org/download/2.10.3/composer.phar -o /usr/local/bin/composer; \
	echo '7a2d379d5b8ffdaa028580ef26494c36d2feef4b178d3dd1473a4dbc5e17c8d6  /usr/local/bin/composer' | sha256sum -c -; \
	chmod 0755 /usr/local/bin/composer; \
	PIE_WORKING_DIRECTORY=/tmp/joomla-pie /tmp/pie install --no-interaction --no-cache --make-parallel-jobs="$(nproc)" apcu/apcu:5.1.28; \
	PIE_WORKING_DIRECTORY=/tmp/joomla-pie /tmp/pie install --no-interaction --no-cache --make-parallel-jobs="$(nproc)" imagick/imagick:3.8.1; \
	PIE_WORKING_DIRECTORY=/tmp/joomla-pie /tmp/pie install --no-interaction --no-cache --make-parallel-jobs="$(nproc)" php-memcached/php-memcached:3.4.0; \
	PIE_WORKING_DIRECTORY=/tmp/joomla-pie /tmp/pie install --no-interaction --no-cache --make-parallel-jobs="$(nproc)" phpredis/phpredis:6.3.0; \
	PIE_WORKING_DIRECTORY=/tmp/joomla-pie /tmp/pie install --no-interaction --no-cache --make-parallel-jobs="$(nproc)" xdebug/xdebug:3.5.3; \
	docker-php-ext-enable opcache; \
	npm_config_cache=/tmp/joomla-npm npm install --global --prefix /usr/local --no-audit --no-fund --engine-strict npm@11.21.1; \
	hash -r; \
	rm -rf /tmp/pie /tmp/joomla-pie /tmp/joomla-npm /tmp/pear /root/.cache; \
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
	printf '%s\n' 'xdebug.mode = develop,debug' 'xdebug.start_with_request = trigger' 'xdebug.start_upon_error = no' 'xdebug.discover_client_host = 0' 'xdebug.client_host = ${JOOMLA_XDEBUG_CLIENT_HOST}' 'xdebug.client_port = ${JOOMLA_XDEBUG_CLIENT_PORT}' 'xdebug.output_dir = /tmp' > /usr/local/etc/php/conf.d/zz-xdebug-settings.ini

VOLUME ["/var/www/html"]
WORKDIR /var/www/html
COPY docker-entrypoint.sh /entrypoint.sh
COPY makedb.php /makedb.php
ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
