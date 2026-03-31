#!/bin/sh
set -eu

HEALTH_FILE="/shared-state/ip-canary-health"

if [ ! -f "$HEALTH_FILE" ]; then
    exit 0
fi

status="$(sed -n 's/^status=//p' "$HEALTH_FILE" | head -n 1)"

[ "$status" = "healthy" ]