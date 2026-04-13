#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="${APP_ROOT:-/app}"
APP_USER="${APP_USER:-application}"
APP_GROUP="${APP_GROUP:-application}"
RESET_SOURCE="${1:-manual}"

SEED_DB_PATH="${APP_ROOT}/seed/demo.sqlite"
SEED_FILEADMIN_PATH="${APP_ROOT}/seed/fileadmin"
RUNTIME_DB_PATH="${APP_ROOT}/var/sqlite/demo.sqlite"
RUNTIME_FILEADMIN_PATH="${APP_ROOT}/public/fileadmin"
LOCK_FILE="/tmp/reset-demo-state.lock"

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

install -d -m 2775 "${APP_ROOT}/var/lock" "${APP_ROOT}/var/transient"
exec 9>"${LOCK_FILE}"

if ! flock -n 9; then
    log "Skipping reset because another reset is already running"
    exit 0
fi

log "Starting baseline restore"

log "Preparing TYPO3 runtime directories"
install -d -m 2775 "${APP_ROOT}/var/cache" "${APP_ROOT}/var/log" "${APP_ROOT}/var/sqlite" "${APP_ROOT}/public" "${APP_ROOT}/public/typo3temp"

require_path "$SEED_DB_PATH"
require_path "$SEED_FILEADMIN_PATH"

log "Verifying PHP SQLite extensions"
php -m | grep -qx 'pdo_sqlite'
php -m | grep -qx 'sqlite3'

log "Restoring SQLite baseline"
tmp_db="$(mktemp "${APP_ROOT}/var/transient/demo.sqlite.XXXXXX")"
cp "$SEED_DB_PATH" "$tmp_db"
mv "$tmp_db" "$RUNTIME_DB_PATH"

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
    "${APP_ROOT}/var" \
    "${APP_ROOT}/public/fileadmin" \
    "${APP_ROOT}/public/typo3temp"

log "Baseline restore complete"
