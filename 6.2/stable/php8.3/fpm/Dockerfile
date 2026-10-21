# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh". DO NOT EDIT.
FROM php:8.3-fpm
LABEL maintainer="Llewellyn van der Merwe <llewellyn.van-der-merwe@community.joomla.org> (@Llewellynvdm), Harald Leithner <harald.leithner@community.joomla.org> (@HLeithner)"

ENV JOOMLA_INSTALLATION_DISABLE_LOCALHOST_CHECK="1"

ENV JOOMLA_VERSION=6.2.0
ENV JOOMLA_SHA512=5d61beed1b2ced52ee96b312d327e8f3616cdd93e5d4a759bef9bc0cee384232a21e3b85e15f659edcdb83fb5ea9969cd009722eeb6151303cc5e6c9d6dc26bc

RUN set -eux; \
	export DEBIAN_FRONTEND=noninteractive; \
	apt-get update; \
	apt-get install -y --no-install-recommends ghostscript; \
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get install -y --no-install-recommends $PHPIZE_DEPS libbz2-dev libgmp-dev libicu-dev libfreetype6-dev libjpeg-dev libldap2-dev libmemcached-dev libmagickwand-dev libpq-dev libpng-dev libwebp-dev libzip-dev automake libtool zlib1g-dev unzip zstd; \
	DEB_BUILD_MULTIARCH="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
	docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
	docker-php-ext-configure ldap "--with-libdir=lib/${DEB_BUILD_MULTIARCH}"; \
	docker-php-ext-install -j "$(nproc)" bz2 bcmath exif gd gmp intl ldap mysqli pdo_mysql pdo_pgsql pgsql zip; \
	docker-php-ext-enable opcache; \
	curl --fail --show-error --silent --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' https://github.com/php/pie/releases/download/1.5.2/pie.phar -o /tmp/pie; \
	echo 'fe70c59738cf56ec00a818cf9cb9593da171aac86f5f1f859995b8839dfd2cc7  /tmp/pie' | sha256sum -c -; \
	chmod 0755 /tmp/pie; \
	curl --fail --show-error --silent --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' https://github.com/krakjoe/apcu/archive/refs/tags/v5.1.27.tar.gz -o /tmp/extension-apcu.tgz; \
	echo 'c4693ad108f80f4d181ece0d4b583c8cd04c9e34d8046c8d03aeb5eed5809316  /tmp/extension-apcu.tgz' | sha256sum -c -; \
	mkdir -p /tmp/extension-apcu; \
	tar -xzf /tmp/extension-apcu.tgz -C /tmp/extension-apcu --strip-components=1 --no-same-owner; \
	PIE_WORKING_DIRECTORY=/tmp/joomla-pie /tmp/pie install --no-interaction --no-cache --working-dir=/tmp/extension-apcu --skip-enable-extension --make-parallel-jobs="$(nproc)"; \
	docker-php-ext-enable --ini-name docker-php-ext-apcu.ini apcu; \
	php -r 'exit(phpversion("apcu") === "5.1.27" ? 0 : 1);'; \
	rm -rf /tmp/extension-apcu /tmp/extension-apcu.tgz; \
	curl --fail --show-error --silent --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' https://github.com/Imagick/imagick/archive/refs/tags/3.8.0.tar.gz -o /tmp/extension-imagick.tgz; \
	echo 'a964e54a441392577f195d91da56e0b3cf30c32e6d60d0531a355b37bb1e1a59  /tmp/extension-imagick.tgz' | sha256sum -c -; \
	mkdir -p /tmp/extension-imagick; \
	tar -xzf /tmp/extension-imagick.tgz -C /tmp/extension-imagick --strip-components=1 --no-same-owner; \
	PIE_WORKING_DIRECTORY=/tmp/joomla-pie /tmp/pie install --no-interaction --no-cache --working-dir=/tmp/extension-imagick --skip-enable-extension --make-parallel-jobs="$(nproc)"; \
	docker-php-ext-enable --ini-name docker-php-ext-imagick.ini imagick; \
	php -r 'exit(phpversion("imagick") === "3.8.0" ? 0 : 1);'; \
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
	printf '%s\n' opcache.memory_consumption=128 opcache.interned_strings_buffer=8 opcache.max_accelerated_files=4000 opcache.revalidate_freq=2 > /usr/local/etc/php/conf.d/opcache-recommended.ini

VOLUME ["/var/www/html"]
WORKDIR /var/www/html
COPY docker-entrypoint.sh /entrypoint.sh
COPY makedb.php /makedb.php
ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
