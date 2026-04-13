FROM webdevops/php-apache:8.5

ENV TYPO3_CONTEXT=Development \
    WEB_DOCUMENT_ROOT=/app/public \
    WEB_DOCUMENT_INDEX=index.php \
    TYPO3_PATH_APP=/app \
    TYPO3_PATH_ROOT=/app/public \
    TYPO3_TRUST_ANY_PROXY=0 \
    RESET_DEMO_CRON_SCHEDULE="0 * * * *" \
    COMPOSER_ALLOW_SUPERUSER=1

WORKDIR /app

RUN docker-service enable cron \
    && apt-get update \
    && apt-get install -y --no-install-recommends graphicsmagick imagemagick rsync sqlite3 gzip util-linux unzip \
    && rm -rf /var/lib/apt/lists/*

COPY composer.json composer.lock /app/

RUN composer install --no-interaction --prefer-dist

COPY . /app
COPY docker/apache/10-typo3.conf /opt/docker/etc/httpd/vhost.common.d/10-typo3.conf
COPY docker/entrypoint/10-prepare-demo.sh /opt/docker/provision/entrypoint.d/10-prepare-demo.sh
COPY scripts/reset-demo-state.sh /usr/local/bin/reset-demo-state

RUN chmod +x /opt/docker/provision/entrypoint.d/10-prepare-demo.sh /usr/local/bin/reset-demo-state \
    && mkdir -p /app/var/cache /app/var/lock /app/var/log /app/var/sqlite /app/var/transient /app/public/fileadmin /app/public/typo3temp \
    && chown -R application:application /app
