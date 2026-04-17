#!/usr/bin/env bash
set -euo pipefail

# read all envs from /proc/1/environ
while IFS= read -r -d '' kv; do
  export "$kv"
done < /proc/1/environ

APP_ROOT="${APP_ROOT:-/app}"
APP_USER="${APP_USER:-application}"
APP_GROUP="${APP_GROUP:-application}"
RESET_SOURCE="${1:-manual}"
RESET_DEMO_DB_WAIT_TIMEOUT="${RESET_DEMO_DB_WAIT_TIMEOUT:-60}"

SEED_MYSQL_DATA_PATH="${APP_ROOT}/seed/demo.mysql.sql.gz"
SEED_FILEADMIN_PATH="${APP_ROOT}/seed/fileadmin"
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
        php ${APP_ROOT}/scripts/parse-database-url.php ${DATABASE_URL}
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

restore_mysql_baseline() {
    require_path "$SEED_MYSQL_DATA_PATH"
    require_path "$TYPO3_BIN"

    log "Verifying PHP MySQL extension"
    php -m | grep -qx 'pdo_mysql'

    wait_for_mysql
    drop_mysql_schema_objects

    log "Set MySQL settings via TYPO3 setup CLI"
    (
        cd "$APP_ROOT"
        php "$TYPO3_BIN" configuration:set DB/Connections/Default/host "$RESET_DATABASE_HOST"
        php "$TYPO3_BIN" configuration:set DB/Connections/Default/port "$RESET_DATABASE_PORT"
        php "$TYPO3_BIN" configuration:set DB/Connections/Default/dbname "$RESET_DATABASE_NAME"
        php "$TYPO3_BIN" configuration:set DB/Connections/Default/user "$RESET_DATABASE_USER"
        php "$TYPO3_BIN" configuration:set DB/Connections/Default/password "$RESET_DATABASE_PASSWORD"
    )

    log "Importing MySQL baseline data"
    gzip -dc "$SEED_MYSQL_DATA_PATH" | mysql_command

    log "Check MySQL schema via TYPO3 database:update"
    (
        cd "$APP_ROOT"
        # run the update command twice to ensure that all schema changes are applied, including those that may be introduced by the first update pass
        php "$TYPO3_BIN" database:update -v '*'
        php "$TYPO3_BIN" database:update -v '*'
    )
    log "Update Langauge packs"
    (
        cd "$APP_ROOT"
        php "$TYPO3_BIN" language:update -v
    )
}

install -d -m 2775 "${APP_ROOT}/var/lock" "${APP_ROOT}/var/transient"
exec 9>"${LOCK_FILE}"

if ! flock -n 9; then
    log "Skipping reset because another reset is already running"
    exit 0
fi

log "Starting baseline restore"

log "Preparing TYPO3 runtime directories"
install -d -m 2775 "${APP_ROOT}/var/cache" "${APP_ROOT}/var/log" "${APP_ROOT}/public" "${APP_ROOT}/public/typo3temp"

require_path "$SEED_FILEADMIN_PATH"
parse_database_url
restore_mysql_baseline

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
