#!/bin/sh
set -eu

. /scripts/messenger/gotify_messenger.sh

CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
USE_GOTIFY="${USE_GOTIFY:-true}"
OBSERVED_HEALTH_FILE="/shared-state/ip-canary-health"
OBSERVED_HEARTBEAT_FILE="/shared-state/ip-canary-heartbeat"
HEARTBEAT_STALE_SECONDS="${HEARTBEAT_STALE_SECONDS:-360}"
OBSERVED_INSTANCE_NAME="observed-instance"

observer_started_without_status=0
first_observation_announced=0
last_state=""

trap 'printf "Received shutdown signal.\n"; exit 0' TERM INT

send_observer_message() {
    title="$1"
    message="$2"

    if [ "$USE_GOTIFY" != "true" ]; then
        return 0
    fi

    if ! send_gotify_message "$title" "$message"; then
        printf 'Failed to send observer message.\n' >&2
        return 1
    fi

    return 0
}

read_kv_value() {
    file_path="$1"
    key="$2"

    if [ ! -f "$file_path" ]; then
        return 1
    fi

    value="$(sed -n "s/^$key=//p" "$file_path" | head -n 1)"
    if [ -z "$value" ]; then
        return 1
    fi

    printf '%s\n' "$value"
}

read_current_observation() {
    observed_state="unknown"
    observed_reason="no status written yet"
    observed_instance="$OBSERVED_INSTANCE_NAME"

    if heartbeat_instance="$(read_kv_value "$OBSERVED_HEARTBEAT_FILE" "writer_instance")"; then
        observed_instance="$heartbeat_instance"
    fi

    if ! heartbeat_epoch="$(read_kv_value "$OBSERVED_HEARTBEAT_FILE" "heartbeat_epoch")"; then
        return 2
    fi

    case "$heartbeat_epoch" in
        ''|*[!0-9]*)
            observed_state="unhealthy"
            observed_reason="invalid heartbeat epoch format"
            return 0
            ;;
    esac

    now_epoch="$(date +%s)"
    age_seconds=$((now_epoch - heartbeat_epoch))
    if [ "$age_seconds" -lt 0 ]; then
        age_seconds=0
    fi

    if [ "$age_seconds" -gt "$HEARTBEAT_STALE_SECONDS" ]; then
        observed_state="unhealthy"
        observed_reason="no healthcheck update written for ${age_seconds}s (threshold ${HEARTBEAT_STALE_SECONDS}s)"
        return 0
    fi

    if ! health_status="$(read_kv_value "$OBSERVED_HEALTH_FILE" "status")"; then
        observed_state="unhealthy"
        observed_reason="heartbeat exists but health status is missing"
        return 0
    fi

    health_reason="$(read_kv_value "$OBSERVED_HEALTH_FILE" "reason" || true)"
    if [ -z "$health_reason" ]; then
        health_reason="no reason recorded"
    fi

    case "$health_status" in
        healthy)
            observed_state="healthy"
            observed_reason="$health_reason"
            ;;
        unhealthy)
            observed_state="unhealthy"
            observed_reason="$health_reason"
            ;;
        *)
            observed_state="unhealthy"
            observed_reason="invalid observed health status '$health_status'"
            ;;
    esac

    return 0
}

announce_startup() {
    if read_current_observation; then
        send_observer_message \
            "IP Canary observer startup" \
            "Observer started and now monitoring health updates for '$observed_instance'. Current state: $observed_state. Reason: $observed_reason."
        first_observation_announced=1
        last_state="$observed_state"
    else
        send_observer_message \
            "IP Canary observer startup" \
            "Observer started and waiting for first health status. No watchdog healthcheck has been written yet. Target label: '$observed_instance'."
        observer_started_without_status=1
        first_observation_announced=0
        last_state=""
    fi
}

announce_startup

while true; do
    if ! read_current_observation; then
        sleep "$CHECK_INTERVAL"
        continue
    fi

    if [ "$observer_started_without_status" -eq 1 ] && [ "$first_observation_announced" -eq 0 ]; then
        send_observer_message \
            "IP Canary observer now observing" \
            "First health status detected. Now observing '$observed_instance'. Current state: $observed_state. Reason: $observed_reason."
        first_observation_announced=1
    fi

    if [ -n "$last_state" ] && [ "$observed_state" != "$last_state" ]; then
        if [ "$observed_state" = "unhealthy" ]; then
            send_observer_message \
                "IP Canary observed service unhealthy" \
                "Observed container '$observed_instance' transitioned from healthy to unhealthy. Reason: $observed_reason."
        else
            send_observer_message \
                "IP Canary observed service healthy" \
                "Observed container '$observed_instance' transitioned from unhealthy to healthy. Reason: $observed_reason."
        fi
    fi

    last_state="$observed_state"
    sleep "$CHECK_INTERVAL"
done
