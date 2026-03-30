#!/bin/sh
set -eu

HEALTH_FILE="${HEALTH_FILE:-/tmp/ip-canary-health}"

if [ ! -f "$HEALTH_FILE" ]; then
    exit 0
fi

status="$(sed -n 's/^status=//p' "$HEALTH_FILE" | head -n 1)"

[ "$status" = "healthy" ]