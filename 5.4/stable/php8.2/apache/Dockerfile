# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh". DO NOT EDIT.
FROM php:8.2-apache
LABEL maintainer="Llewellyn van der Merwe <llewellyn.van-der-merwe@community.joomla.org> (@Llewellynvdm), Harald Leithner <harald.leithner@community.joomla.org> (@HLeithner)"

ENV JOOMLA_INSTALLATION_DISABLE_LOCALHOST_CHECK="1"

ENV JOOMLA_VERSION=5.4.10
ENV JOOMLA_SHA512=31a29996d6234aa8d73384abd9ad91a1b7865cef79a17e747c389164ecf5f7c47deefcb38cd18ebf57eb409d10f531152c390caf7da50e6ad403acc32c791832

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
	curl --fail --show-error --silent --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' https://github.com/php/pie/releases/download/1.5.2/pie.phar -o /tmp/pie; \
	echo 'fe70c59738cf56ec00a818cf9cb9593da171aac86f5f1f859995b8839dfd2cc7  /tmp/pie' | sha256sum -c -; \
	chmod 0755 /tmp/pie; \
	PIE_WORKING_DIRECTORY=/tmp/joomla-pie /tmp/pie install --no-interaction --no-cache --make-parallel-jobs="$(nproc)" apcu/apcu:5.1.26; \
	PIE_WORKING_DIRECTORY=/tmp/joomla-pie /tmp/pie install --no-interaction --no-cache --make-parallel-jobs="$(nproc)" imagick/imagick:3.8.0; \
	PIE_WORKING_DIRECTORY=/tmp/joomla-pie /tmp/pie install --no-interaction --no-cache --make-parallel-jobs="$(nproc)" php-memcached/php-memcached:3.3.0; \
	PIE_WORKING_DIRECTORY=/tmp/joomla-pie /tmp/pie install --no-interaction --no-cache --make-parallel-jobs="$(nproc)" phpredis/phpredis:6.2.0; \
	docker-php-ext-enable opcache; \
	rm -rf /tmp/pie /tmp/joomla-pie /tmp/joomla-npm /tmp/pear /root/.cache; \
	curl --fail --show-error --silent --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' https://github.com/joomla/joomla-cms/releases/download/5.4.10/Joomla_5.4.10-Stable-Full_Package.tar.zst -o /tmp/joomla.tar.zst; \
	echo '31a29996d6234aa8d73384abd9ad91a1b7865cef79a17e747c389164ecf5f7c47deefcb38cd18ebf57eb409d10f531152c390caf7da50e6ad403acc32c791832  /tmp/joomla.tar.zst' | sha512sum -c -; \
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
