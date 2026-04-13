#!/usr/bin/env bash
set -euo pipefail

RESET_DEMO_CRON_SCHEDULE="${RESET_DEMO_CRON_SCHEDULE:-0 * * * *}"
CRON_FILE="/etc/cron.d/reset-demo-state"
CRON_PATH="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

configure_reset_schedule() {
    case "$RESET_DEMO_CRON_SCHEDULE" in
        disabled|off|none)
            rm -f "$CRON_FILE"
            printf '[reset-demo-state][startup] Scheduled reset disabled via RESET_DEMO_CRON_SCHEDULE=%s\n' "$RESET_DEMO_CRON_SCHEDULE"
            return
            ;;
    esac

    if [ -z "${RESET_DEMO_CRON_SCHEDULE// }" ]; then
        printf 'RESET_DEMO_CRON_SCHEDULE must not be empty\n' >&2
        exit 1
    fi

    if printf '%s' "$RESET_DEMO_CRON_SCHEDULE" | grep -q '[[:cntrl:]]'; then
        printf 'RESET_DEMO_CRON_SCHEDULE contains unsupported control characters\n' >&2
        exit 1
    fi

    {
        printf '%s\n\n' "$CRON_PATH"
        printf '%s root /usr/local/bin/reset-demo-state scheduled >/proc/1/fd/1 2>/proc/1/fd/2\n' "$RESET_DEMO_CRON_SCHEDULE"
    } > "$CRON_FILE"

    chmod 0644 "$CRON_FILE"
    printf '[reset-demo-state][startup] Scheduled reset configured: %s\n' "$RESET_DEMO_CRON_SCHEDULE"
}

configure_reset_schedule
/usr/local/bin/reset-demo-state startup
