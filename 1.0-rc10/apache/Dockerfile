FROM php:7.4-apache-buster

# entrypoint.sh and cron.sh dependencies
RUN set -ex; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
		rsync \
		busybox-static \
		postgresql-client \
	; \
	rm -rf /var/lib/apt/lists/*; \
	\
	mkdir -p /var/spool/cron/crontabs; \
	echo '*/5 * * * * php /var/www/html/schedule.php' > /var/spool/cron/crontabs/www-data

# utilities
RUN set -ex; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
		vim \
	; \
	rm -rf /var/lib/apt/lists/*

# install the PHP extensions flyspray needs
ENV PHP_MEMORY_LIMIT 512M
ENV PHP_UPLOAD_LIMIT 512M

RUN set -ex; \
	#
	apt-get update; \
	apt-get install -y --no-install-recommends \
		zlib1g-dev \
		zip \
		libzip-dev \
		libpng-dev \
		libjpeg62-turbo-dev \
		libfreetype6-dev \
		libssl-dev \
		libpq-dev \
		libmcrypt-dev; \
	docker-php-ext-configure gd --with-freetype --with-jpeg; \
	docker-php-ext-install -j "$(nproc)" \
		gd \
		mysqli \
		pgsql \
		pdo_mysql \
		pdo \
		pdo_pgsql \
		exif \
		zip \
	;

RUN set -ex; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*

# set recommended PHP.ini settings
RUN mkdir /var/www/data; \
	chown -R www-data:root /var/www; \
	chmod -R g=u /var/www

VOLUME /var/www/html

RUN a2enmod headers rewrite remoteip ;\
    {\
     echo RemoteIPHeader X-Real-IP ;\
     echo RemoteIPTrustedProxy 10.0.0.0/8 ;\
     echo RemoteIPTrustedProxy 172.16.0.0/12 ;\
     echo RemoteIPTrustedProxy 192.168.0.0/16 ;\
    } > /etc/apache2/conf-available/remoteip.conf;\
    a2enconf remoteip

ENV FLYSPRAY_VERSION 1.0-rc10

RUN set -ex; \
	fetchDeps=" \
		\
	"; \
	apt-get update; \
	apt-get install -y --no-install-recommends $fetchDeps; \
	curl -fsSL -o flyspray.tar.gz \
		"https://github.com/Flyspray/flyspray/archive/v1.0-rc10.tar.gz"; \
  tar -xzf flyspray.tar.gz -C /usr/src; \
  rm flyspray.tar.gz; \
	mv /usr/src/flyspray-1.0-rc10 /usr/src/flyspray; \
	cd /usr/src/flyspray; \
	curl -sS https://getcomposer.org/installer | php; \
	php composer.phar install --no-dev

RUN set -ex; \
	\
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*

COPY *.sh upgrade.exclude /
#COPY config/* /usr/src/flyspray/config

ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]
