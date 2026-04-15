FROM webdevops/php-apache:8.5

ENV TYPO3_CONTEXT=Development \
    WEB_DOCUMENT_ROOT=/app/public \
    WEB_DOCUMENT_INDEX=index.php \
    TYPO3_PATH_APP=/app \
    TYPO3_PATH_ROOT=/app/public \
    TYPO3_TRUST_ANY_PROXY=0 \
    RESET_DEMO_CRON_SCHEDULE="0 0 * * *" \
    COMPOSER_ALLOW_SUPERUSER=1

WORKDIR /app

RUN docker-service enable cron \
    && apt-get update \
    && apt-get install -y --no-install-recommends default-mysql-client graphicsmagick imagemagick rsync gzip util-linux unzip \
    && rm -rf /var/lib/apt/lists/*

USER application

COPY --chown=application:application composer.json composer.lock /app/

RUN composer install --no-interaction --prefer-dist

COPY --chown=application:application . /app
COPY --chown=application:application docker/apache/10-typo3.conf /opt/docker/etc/httpd/vhost.common.d/10-typo3.conf
COPY --chown=application:application docker/entrypoint/10-prepare-demo.sh /opt/docker/provision/entrypoint.d/10-prepare-demo.sh
COPY --chown=application:application docker/php/10-warning-handling.ini /usr/local/etc/php/conf.d/10-warning-handling.ini
COPY --chown=application:application scripts/reset-demo-state.sh /usr/local/bin/reset-demo-state

RUN chmod +x /opt/docker/provision/entrypoint.d/10-prepare-demo.sh /usr/local/bin/reset-demo-state \
    && mkdir -p /app/var/cache /app/var/lock /app/var/log /app/var/transient /app/public/fileadmin /app/public/typo3temp

USER root
