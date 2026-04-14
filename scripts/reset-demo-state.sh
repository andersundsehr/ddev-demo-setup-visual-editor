#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="${APP_ROOT:-/app}"
APP_USER="${APP_USER:-application}"
APP_GROUP="${APP_GROUP:-application}"
RESET_SOURCE="${1:-manual}"
RESET_DEMO_DB_WAIT_TIMEOUT="${RESET_DEMO_DB_WAIT_TIMEOUT:-60}"

SEED_DB_PATH="${APP_ROOT}/seed/demo.sqlite"
SEED_MYSQL_DATA_PATH="${APP_ROOT}/seed/demo.mysql.sql.gz"
SEED_FILEADMIN_PATH="${APP_ROOT}/seed/fileadmin"
RUNTIME_DB_PATH="${APP_ROOT}/var/sqlite/demo.sqlite"
RUNTIME_FILEADMIN_PATH="${APP_ROOT}/public/fileadmin"
LOCK_FILE="/tmp/reset-demo-state.lock"
TYPO3_BIN="${APP_ROOT}/vendor/bin/typo3"

log() {
    printf '[reset-demo-state][%s][%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${RESET_SOURCE}" "$1"
}

require_path() {
    local path="$1"
    if [ ! -e "$path" ]; then
        printf 'Required path is missing: %s\n' "$path" >&2
        exit 1
    fi
}

php_eval() {
    php -r "$1"
}

parse_database_url() {
    local exports

    exports="$(
        APP_ROOT="$APP_ROOT" DATABASE_URL="${DATABASE_URL:-}" php <<'PHP'
<?php
$appRoot = getenv('APP_ROOT') ?: '/app';
$parseDatabaseUrl = require $appRoot . '/scripts/database-url.php';
$databaseConfiguration = $parseDatabaseUrl(getenv('DATABASE_URL') ?: null);

if ($databaseConfiguration === null) {
    $databaseConfiguration = [
        'scheme' => 'sqlite',
        'path' => $appRoot . '/var/sqlite/demo.sqlite',
    ];
}

$variables = match ($databaseConfiguration['scheme']) {
    'sqlite' => [
        'RESET_DATABASE_BACKEND' => 'sqlite',
        'RESET_DATABASE_PATH' => $databaseConfiguration['path'],
    ],
    'mysql' => [
        'RESET_DATABASE_BACKEND' => 'mysql',
        'RESET_DATABASE_HOST' => $databaseConfiguration['host'],
        'RESET_DATABASE_PORT' => (string)$databaseConfiguration['port'],
        'RESET_DATABASE_NAME' => $databaseConfiguration['dbname'],
        'RESET_DATABASE_USER' => $databaseConfiguration['user'],
        'RESET_DATABASE_PASSWORD' => $databaseConfiguration['password'],
    ],
    default => throw new RuntimeException(sprintf('Unsupported reset backend "%s"', $databaseConfiguration['scheme'])),
};

foreach ($variables as $key => $value) {
    $escapedValue = str_replace("'", "'\"'\"'", (string)$value);
    echo $key . "='" . $escapedValue . "'" . PHP_EOL;
}
PHP
    )"

    eval "$exports"
}

mysql_command() {
    local -a command

    command=(
        mysql
        --protocol=TCP
        --host="$RESET_DATABASE_HOST"
        --port="$RESET_DATABASE_PORT"
        --user="$RESET_DATABASE_USER"
        --database="$RESET_DATABASE_NAME"
        --default-character-set=utf8mb4
        --silent
        --skip-column-names
    )

    if [ -n "${RESET_DATABASE_PASSWORD:-}" ]; then
        MYSQL_PWD="$RESET_DATABASE_PASSWORD" "${command[@]}" "$@"
        return
    fi

    "${command[@]}" "$@"
}

wait_for_mysql() {
    local elapsed=0

    log "Waiting for MySQL at ${RESET_DATABASE_HOST}:${RESET_DATABASE_PORT}/${RESET_DATABASE_NAME}"
    until mysql_command --execute='SELECT 1' >/dev/null 2>&1; do
        elapsed=$((elapsed + 1))
        if [ "$elapsed" -ge "$RESET_DEMO_DB_WAIT_TIMEOUT" ]; then
            log "Timed out waiting for MySQL after ${RESET_DEMO_DB_WAIT_TIMEOUT}s"
            exit 1
        fi
        sleep 1
    done
}

drop_mysql_schema_objects() {
    log "Dropping existing MySQL tables and views"
    mysql_command >/dev/null <<'SQL'
SET FOREIGN_KEY_CHECKS = 0;
SET @dropTables = (
    SELECT GROUP_CONCAT(CONCAT('`', table_name, '`') ORDER BY table_name SEPARATOR ', ')
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
      AND table_type = 'BASE TABLE'
);
SET @dropTablesStatement = IF(
    @dropTables IS NULL,
    'SELECT 1',
    CONCAT('DROP TABLE IF EXISTS ', @dropTables)
);
PREPARE dropTablesStatement FROM @dropTablesStatement;
EXECUTE dropTablesStatement;
DEALLOCATE PREPARE dropTablesStatement;
SET @dropViews = (
    SELECT GROUP_CONCAT(CONCAT('`', table_name, '`') ORDER BY table_name SEPARATOR ', ')
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
      AND table_type = 'VIEW'
);
SET @dropViewsStatement = IF(
    @dropViews IS NULL,
    'SELECT 1',
    CONCAT('DROP VIEW IF EXISTS ', @dropViews)
);
PREPARE dropViewsStatement FROM @dropViewsStatement;
EXECUTE dropViewsStatement;
DEALLOCATE PREPARE dropViewsStatement;
SET FOREIGN_KEY_CHECKS = 1;
SQL
}

restore_sqlite_baseline() {
    require_path "$SEED_DB_PATH"

    log "Verifying PHP SQLite extensions"
    php -m | grep -qx 'pdo_sqlite'
    php -m | grep -qx 'sqlite3'

    log "Restoring SQLite baseline"
    tmp_db="$(mktemp "${APP_ROOT}/var/transient/demo.sqlite.XXXXXX")"
    cp "$SEED_DB_PATH" "$tmp_db"
    mv "$tmp_db" "$RUNTIME_DB_PATH"
}

restore_mysql_baseline() {
    require_path "$SEED_MYSQL_DATA_PATH"
    require_path "$TYPO3_BIN"

    log "Verifying PHP MySQL extension"
    php -m | grep -qx 'pdo_mysql'

    wait_for_mysql
    drop_mysql_schema_objects

    log "Rebuilding MySQL schema via TYPO3 setup CLI"
    (
        cd "$APP_ROOT"
        php "$TYPO3_BIN" setup \
            --force \
            --no-interaction \
            --driver=pdoMysql \
            --host="$RESET_DATABASE_HOST" \
            --port="$RESET_DATABASE_PORT" \
            --dbname="$RESET_DATABASE_NAME" \
            --username="$RESET_DATABASE_USER" \
            --password="$RESET_DATABASE_PASSWORD" \
            --admin-username=admin \
            --admin-user-password='DemoAdminPassword1!' \
            --admin-email=demo@example.invalid \
            --project-name='Visual Editor Demo' \
            --server-type=apache
    )

    log "Importing MySQL baseline data"
    gzip -dc "$SEED_MYSQL_DATA_PATH" | mysql_command
}

install -d -m 2775 "${APP_ROOT}/var/lock" "${APP_ROOT}/var/transient"
exec 9>"${LOCK_FILE}"

if ! flock -n 9; then
    log "Skipping reset because another reset is already running"
    exit 0
fi

log "Starting baseline restore"

log "Preparing TYPO3 runtime directories"
install -d -m 2775 "${APP_ROOT}/var/cache" "${APP_ROOT}/var/log" "${APP_ROOT}/var/sqlite" "${APP_ROOT}/public" "${APP_ROOT}/public/typo3temp"

require_path "$SEED_FILEADMIN_PATH"
parse_database_url

case "$RESET_DATABASE_BACKEND" in
    sqlite)
        restore_sqlite_baseline
        ;;
    mysql)
        restore_mysql_baseline
        ;;
    *)
        log "Unsupported database backend: ${RESET_DATABASE_BACKEND}"
        exit 1
        ;;
esac

log "Restoring fileadmin baseline"
tmp_fileadmin="$(mktemp -d "${APP_ROOT}/var/transient/fileadmin.XXXXXX")"
rsync -a --delete "${SEED_FILEADMIN_PATH}/" "${tmp_fileadmin}/"
rm -rf "$RUNTIME_FILEADMIN_PATH"
mv "$tmp_fileadmin" "$RUNTIME_FILEADMIN_PATH"

log "Clearing TYPO3 transient state"
rm -rf "${APP_ROOT}/var/cache"
rm -rf "${APP_ROOT}/var/lock"
rm -rf "${APP_ROOT}/public/typo3temp"
install -d -m 2775 "${APP_ROOT}/var/cache" "${APP_ROOT}/var/lock" "${APP_ROOT}/public/typo3temp"
printf '<html><body></body></html>\n' > "${APP_ROOT}/public/typo3temp/index.html"

log "Applying ownership for web runtime"
chown -R "${APP_USER}:${APP_GROUP}" \
    "${APP_ROOT}/config/system" \
    "${APP_ROOT}/var" \
    "${APP_ROOT}/public/fileadmin" \
    "${APP_ROOT}/public/typo3temp"

chmod ug+rw "${APP_ROOT}/config/system/settings.php" "${APP_ROOT}/config/system/additional.php"

log "Baseline restore complete"
