#!/bin/sh
set -eu

. /scripts/base_ip_provider/ip_provider.sh
. /scripts/health/health_state.sh

IP_CHECKER_PORT="${IP_CHECKER_PORT:-9516}"
IP_REFRESH_INTERVAL="${IP_REFRESH_INTERVAL:-10}"
WWW_DIR="/tmp/ip-checker-www"

case "$IP_REFRESH_INTERVAL" in
	''|*[!0-9]*)
		printf 'IP_REFRESH_INTERVAL must be a positive integer.\n' >&2
		exit 1
		;;
esac

if [ "$IP_REFRESH_INTERVAL" -lt 1 ]; then
	printf 'IP_REFRESH_INTERVAL must be at least 1.\n' >&2
	exit 1
fi

mkdir -p "$WWW_DIR"
if [ ! -f "$WWW_DIR/public-ip" ]; then
	printf '%s' "unavailable" >"$WWW_DIR/public-ip"
fi

update_public_ip_file() {
	if current_ip="$(get_container_public_ip)"; then
		tmp_file="$(mktemp)"
		printf '%s' "$current_ip" >"$tmp_file"
		mv "$tmp_file" "$WWW_DIR/public-ip"
		mark_healthy "ip_provider refreshed public IP"
	else
		mark_unhealthy "ip_provider failed to refresh public IP"
		printf 'Unable to refresh current public IP.\n' >&2
	fi
}

update_loop() {
	while true; do
		update_public_ip_file
		sleep "$IP_REFRESH_INTERVAL"
	done
}

update_loop &
updater_pid="$!"

cleanup() {
	kill "$updater_pid" >/dev/null 2>&1 || true
}

trap cleanup TERM INT EXIT

mark_healthy "ip_provider started"

exec httpd -f -p "$IP_CHECKER_PORT" -h "$WWW_DIR"