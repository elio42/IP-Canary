#!/bin/sh
set -eu

. /scripts/base_ip_provider/ip_provider.sh
. /scripts/messenger/gotify_messenger.sh
. /scripts/health/health_state.sh

CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
USE_GOTIFY="${USE_GOTIFY:-false}"
MESSAGE_REPEAT_MINUTES="${MESSAGE_REPEAT_MINUTES:-30}"
MESSAGE_REPEAT_SECONDS=$((MESSAGE_REPEAT_MINUTES * 60))
PROVIDER_FAILURE_TOLERANCE="${PROVIDER_FAILURE_TOLERANCE:-3}"

last_leak_alert_ts=0
last_provider_alert_ts=0
consecutive_provider_failures=0

trap 'printf "Received shutdown signal.\n"; exit 0' TERM INT

mark_healthy "watchdog started"

maybe_send_rate_limited_gotify() {
    category="$1"
    title="$2"
    message="$3"

    if [ "$USE_GOTIFY" != "true" ]; then
        return 0
    fi

    now_ts="$(date +%s)"
    last_ts=0

    case "$category" in
        leak)
            last_ts="$last_leak_alert_ts"
            ;;
        provider)
            last_ts="$last_provider_alert_ts"
            ;;
        *)
            return 1
            ;;
    esac

    if [ "$last_ts" -ne 0 ] && [ $((now_ts - last_ts)) -lt "$MESSAGE_REPEAT_SECONDS" ]; then
        return 0
    fi

    if send_gotify_message "$title" "$message"; then
        printf 'Gotify alert sent successfully.\n'
        case "$category" in
            leak)
                last_leak_alert_ts="$now_ts"
                ;;
            provider)
                last_provider_alert_ts="$now_ts"
                ;;
        esac
    else
        mark_unhealthy "gotify runtime send failed"
        printf 'Failed to send Gotify alert.\n' >&2
    fi
}

while true; do
    if ! current_ip="$(get_container_public_ip)"; then
        mark_unhealthy "failed to fetch container public IP"
        printf 'Failed to fetch container public IP.\n' >&2
        consecutive_provider_failures=$((consecutive_provider_failures + 1))
        if [ "$consecutive_provider_failures" -ge "$PROVIDER_FAILURE_TOLERANCE" ]; then
            maybe_send_rate_limited_gotify "provider" "IP Canary provider failure" "Failed to fetch container public IP from configured provider for $consecutive_provider_failures consecutive checks."
        fi
        sleep "$CHECK_INTERVAL"
        continue
    fi

    if ! expected_ip="$(get_expected_public_ip)"; then
        mark_unhealthy "failed to resolve expected public IP"
        printf 'Failed to resolve expected public IP.\n' >&2
        consecutive_provider_failures=$((consecutive_provider_failures + 1))
        if [ "$consecutive_provider_failures" -ge "$PROVIDER_FAILURE_TOLERANCE" ]; then
            maybe_send_rate_limited_gotify "provider" "IP Canary provider failure" "Failed to resolve expected public IP from REAL_IP_URL/PUBLIC_IP source for $consecutive_provider_failures consecutive checks."
        fi
        sleep "$CHECK_INTERVAL"
        continue
    fi

    # Reset provider failure cooldown after a successful resolution cycle.
    consecutive_provider_failures=0
    last_provider_alert_ts=0

    if [ "$current_ip" = "$expected_ip" ]; then
        mark_unhealthy "container public IP matches expected real IP"
        printf 'ALERT: current IP (%s) matches expected real IP (%s).\n' "$current_ip" "$expected_ip"
        maybe_send_rate_limited_gotify "leak" "IP Canary alert" "Public IP leak detected. Current IP $current_ip matches expected real IP."
    else
        mark_healthy "current IP differs from expected real IP"
        # printf 'Safe: current IP (%s) differs from expected real IP (%s).\n' "$current_ip" "$expected_ip"
        last_leak_alert_ts=0
    fi

    sleep "$CHECK_INTERVAL"
done