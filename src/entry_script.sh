#!/bin/sh
set -eu

. /scripts/messenger/gotify_messenger.sh

fail() {
	printf '%s\n' "$1" >&2
	exit 1
}

normalize_bool() {
	value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
	case "$value" in
		true|1|yes|on)
			printf 'true\n'
			;;
		false|0|no|off|'')
			printf 'false\n'
			;;
		*)
			return 1
			;;
	esac
}

validate_interval() {
	value="$1"
	case "$value" in
		''|*[!0-9]*)
			return 1
			;;
	esac

	if [ "$value" -lt 1 ]; then
		return 1
	fi

	return 0
}

validate_non_negative_integer() {
	value="$1"
	case "$value" in
		''|*[!0-9]*)
			return 1
			;;
	esac

	return 0
}

MODE="${MODE:-}"
if [ -z "$MODE" ]; then
	fail "MODE must be set to watchdog or ip_provider."
fi

CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
if ! validate_interval "$CHECK_INTERVAL"; then
	fail "CHECK_INTERVAL must be a positive integer."
fi
export CHECK_INTERVAL

MESSAGE_REPEAT_SECONDS="${MESSAGE_REPEAT_SECONDS:-1800}"
if ! validate_interval "$MESSAGE_REPEAT_SECONDS"; then
	fail "MESSAGE_REPEAT_SECONDS must be a positive integer."
fi
export MESSAGE_REPEAT_SECONDS

PROVIDER_FAILURE_TOLERANCE="${PROVIDER_FAILURE_TOLERANCE:-3}"
if ! validate_non_negative_integer "$PROVIDER_FAILURE_TOLERANCE"; then
	fail "PROVIDER_FAILURE_TOLERANCE must be a non-negative integer."
fi
export PROVIDER_FAILURE_TOLERANCE

INSTANCE_NAME="${INSTANCE_NAME:-${HOSTNAME:-}}"
if [ -z "$INSTANCE_NAME" ]; then
	INSTANCE_NAME="$(hostname)"
fi
export INSTANCE_NAME

HEARTBEAT_STALE_SECONDS="${HEARTBEAT_STALE_SECONDS:-360}"
if ! validate_interval "$HEARTBEAT_STALE_SECONDS"; then
	fail "HEARTBEAT_STALE_SECONDS must be a positive integer."
fi
export HEARTBEAT_STALE_SECONDS

USE_GOTIFY_NORMALIZED="$(normalize_bool "${USE_GOTIFY:-true}")" || fail "USE_GOTIFY must be a boolean value."
export USE_GOTIFY="$USE_GOTIFY_NORMALIZED"

case "$MODE" in
	watchdog)
		if [ -z "${PUBLIC_IP:-}" ] && [ -z "${REAL_IP_URL:-}" ]; then
			fail "watchdog mode requires PUBLIC_IP or REAL_IP_URL."
		fi

		if [ "$USE_GOTIFY" = "true" ]; then
			[ -n "${GOTIFY_URL:-}" ] || fail "GOTIFY_URL is required when USE_GOTIFY=true."
			[ -n "${GOTIFY_API_KEY:-}" ] || fail "GOTIFY_API_KEY is required when USE_GOTIFY=true."
		fi

		exec sh /scripts/watchdog/watchdog.sh
		;;
	ip_provider)
		exec sh /scripts/ip_provider/ip_provider.sh
		;;
	heartbeat_observer)
		if [ "$USE_GOTIFY" = "true" ]; then
			[ -n "${GOTIFY_URL:-}" ] || fail "GOTIFY_URL is required when USE_GOTIFY=true."
			[ -n "${GOTIFY_API_KEY:-}" ] || fail "GOTIFY_API_KEY is required when USE_GOTIFY=true."
		fi

		exec sh /scripts/heartbeat/heartbeat_observer.sh
		;;
	*)
		fail "Unsupported MODE '$MODE'. Use watchdog, ip_provider, or heartbeat_observer."
		;;
esac
