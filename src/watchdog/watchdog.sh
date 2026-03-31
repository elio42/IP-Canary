#!/bin/sh
set -eu

. /scripts/base_ip_provider/ip_provider.sh
. /scripts/messenger/gotify_messenger.sh
. /scripts/health/health_state.sh

CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
USE_GOTIFY="${USE_GOTIFY:-false}"
MESSAGE_REPEAT_SECONDS="${MESSAGE_REPEAT_SECONDS:-1800}"
PROVIDER_FAILURE_TOLERANCE="${PROVIDER_FAILURE_TOLERANCE:-3}"

last_leak_alert_ts=0
last_provider_alert_ts=0
consecutive_provider_failures=0
startup_status_sent=0

trap 'printf "Received shutdown signal.\n"; exit 0' TERM INT

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

maybe_send_startup_status() {
    current_ip="$1"
    expected_ip="$2"
    expected_source="$3"
    error_summary="$4"
    health_state="$5"
    health_reason="$6"

    if [ "$startup_status_sent" -eq 1 ]; then
        return 0
    fi

    if [ "$USE_GOTIFY" != "true" ]; then
        startup_status_sent=1
        return 0
    fi

    if [ -z "$error_summary" ]; then
        error_summary="none"
    fi

    if [ -z "$health_reason" ]; then
        health_reason="none"
    fi

    if ! send_gotify_message \
        "IP Canary startup status" \
        "Startup status snapshot: state: $health_state, reason: $health_reason, expected IP ($expected_source): $expected_ip, measured IP: $current_ip, current errors: $error_summary."; then
        printf 'Failed to send startup status message.\n' >&2
        return 1
    fi

    startup_status_sent=1
}

while true; do
    current_ip="unavailable"
    expected_ip="unavailable"
    if [ -n "${REAL_IP_URL:-}" ]; then
        expected_source="REAL_IP_URL"
    else
        expected_source="PUBLIC_IP"
    fi
    error_summary=""
    current_health_state="unhealthy"
    current_health_reason="status not yet evaluated"

    if ! current_ip="$(get_container_public_ip)"; then
        printf 'Failed to fetch container public IP.\n' >&2
        error_summary="failed to fetch measured public IP"
    fi

    if ! expected_ip="$(get_expected_public_ip)"; then
        printf 'Failed to resolve expected public IP.\n' >&2
        if [ -n "$error_summary" ]; then
            error_summary="$error_summary; failed to resolve expected public IP"
        else
            error_summary="failed to resolve expected public IP"
        fi
    fi

    if [ -n "$error_summary" ]; then
        consecutive_provider_failures=$((consecutive_provider_failures + 1))
        startup_was_sent="$startup_status_sent"

        if [ "$consecutive_provider_failures" -ge "$PROVIDER_FAILURE_TOLERANCE" ]; then
            current_health_state="unhealthy"
            current_health_reason="provider failures reached tolerance: $error_summary"
            mark_unhealthy "$current_health_reason"
            maybe_send_startup_status "$current_ip" "$expected_ip" "$expected_source" "$error_summary" "$current_health_state" "$current_health_reason"
            if [ "$startup_was_sent" -eq 1 ]; then
                maybe_send_rate_limited_gotify "provider" "IP Canary provider failure" "Provider-related IP checks failed for $consecutive_provider_failures consecutive checks. Current errors: $error_summary."
            fi
        else
            current_health_state="healthy"
            current_health_reason="provider failures below tolerance: $consecutive_provider_failures/$PROVIDER_FAILURE_TOLERANCE"
            maybe_send_startup_status "$current_ip" "$expected_ip" "$expected_source" "$error_summary" "$current_health_state" "$current_health_reason"
        fi

        sleep "$CHECK_INTERVAL"
        continue
    fi

    # Reset provider failure cooldown after a successful resolution cycle.
    consecutive_provider_failures=0
    last_provider_alert_ts=0

    if [ "$current_ip" = "$expected_ip" ]; then
        startup_was_sent="$startup_status_sent"
        current_health_state="unhealthy"
        current_health_reason="container public IP matches expected real IP"
        mark_unhealthy "$current_health_reason"
        printf 'ALERT: current IP (%s) matches expected real IP (%s).\n' "$current_ip" "$expected_ip"

        maybe_send_startup_status "$current_ip" "$expected_ip" "$expected_source" "none" "$current_health_state" "$current_health_reason"
        if [ "$startup_was_sent" -eq 1 ]; then
            maybe_send_rate_limited_gotify "leak" "IP Canary alert" "Public IP leak detected. Current IP $current_ip matches expected real IP."
        fi
    else
        current_health_state="healthy"
        current_health_reason="current IP differs from expected real IP"
        mark_healthy "$current_health_reason"
        # printf 'Safe: current IP (%s) differs from expected real IP (%s).\n' "$current_ip" "$expected_ip"
        last_leak_alert_ts=0

        maybe_send_startup_status "$current_ip" "$expected_ip" "$expected_source" "none" "$current_health_state" "$current_health_reason"
    fi

    sleep "$CHECK_INTERVAL"
done