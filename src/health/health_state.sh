#!/bin/sh

HEALTH_FILE="${HEALTH_FILE:-/tmp/ip-canary-health}"

write_health_state() {
    status="$1"
    reason="$2"

    {
        printf 'status=%s\n' "$status"
        printf 'timestamp=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        printf 'reason=%s\n' "$reason"
    } >"$HEALTH_FILE"
}

mark_healthy() {
    write_health_state "healthy" "${1:-ok}"
}

mark_unhealthy() {
    write_health_state "unhealthy" "${1:-error}"
}