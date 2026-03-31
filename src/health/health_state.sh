#!/bin/sh

HEALTH_FILE="/shared-state/ip-canary-health"
HEARTBEAT_FILE="/shared-state/ip-canary-heartbeat"

write_health_state() {
    status="$1"
    reason="$2"
    now_epoch="$(date +%s)"
    writer_instance="${INSTANCE_NAME:-${HOSTNAME:-unknown-instance}}"
    mkdir -p "/shared-state"

    {
        printf 'status=%s\n' "$status"
        printf 'timestamp=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        printf 'reason=%s\n' "$reason"
    } >"$HEALTH_FILE"

    {
        printf 'heartbeat_epoch=%s\n' "$now_epoch"
        printf 'writer_instance=%s\n' "$writer_instance"
        printf 'writer_status=%s\n' "$status"
        printf 'writer_reason=%s\n' "$reason"
    } >"$HEARTBEAT_FILE"
}

mark_healthy() {
    write_health_state "healthy" "${1:-ok}"
}

mark_unhealthy() {
    write_health_state "unhealthy" "${1:-error}"
}