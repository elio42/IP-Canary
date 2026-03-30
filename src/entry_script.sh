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

MESSAGE_REPEAT_MINUTES="${MESSAGE_REPEAT_MINUTES:-30}"
if ! validate_interval "$MESSAGE_REPEAT_MINUTES"; then
	fail "MESSAGE_REPEAT_MINUTES must be a positive integer."
fi
export MESSAGE_REPEAT_MINUTES

PROVIDER_FAILURE_TOLERANCE="${PROVIDER_FAILURE_TOLERANCE:-3}"
if ! validate_non_negative_integer "$PROVIDER_FAILURE_TOLERANCE"; then
	fail "PROVIDER_FAILURE_TOLERANCE must be a non-negative integer."
fi
export PROVIDER_FAILURE_TOLERANCE

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

			if ! send_gotify_message "IP Canary startup test" "Startup connectivity check for watchdog mode."; then
				fail "Startup Gotify test failed. Exiting."
			fi
		fi

		exec sh /scripts/watchdog/watchdog.sh
		;;
	ip_provider)
		exec sh /scripts/ip_provider/ip_provider.sh
		;;
	*)
		fail "Unsupported MODE '$MODE'. Use watchdog or ip_provider."
		;;
esac
