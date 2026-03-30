#!/bin/sh

DEFAULT_IP_PROVIDER_URL="https://api.ipify.org"
HTTP_TIMEOUT="${HTTP_TIMEOUT:-10}"

LAST_HTTP_STATUS=""
LAST_HTTP_URL=""

trim_text() {
	printf '%s' "$1" | tr -d ' \t\r\n'
}

http_get() {
	url="$1"
	tmp_file="$(mktemp)"

	LAST_HTTP_URL="$url"
	LAST_HTTP_STATUS=""

	status="$(curl -sS -L --max-time "$HTTP_TIMEOUT" -o "$tmp_file" -w "%{http_code}" "$url")"
	curl_rc="$?"
	body="$(cat "$tmp_file")"
	rm -f "$tmp_file"

	if [ "$curl_rc" -ne 0 ]; then
		HTTP_BODY=""
		return 1
	fi

	LAST_HTTP_STATUS="$status"
	HTTP_BODY="$body"

	if [ "$status" != "200" ]; then
		return 22
	fi

	return 0
}

get_container_public_ip() {
	provider_url="${IP_PROVIDER_URL:-$DEFAULT_IP_PROVIDER_URL}"

	http_get "$provider_url"
	rc="$?"
	if [ "$rc" -ne 0 ]; then
		return "$rc"
	fi

	current_ip="$(trim_text "$HTTP_BODY")"
	if [ -z "$current_ip" ]; then
		return 3
	fi

	printf '%s\n' "$current_ip"
	return 0
}

get_expected_public_ip() {
	# Prefer REAL_IP_URL when both are provided.
	if [ -n "${REAL_IP_URL:-}" ]; then
		http_get "$REAL_IP_URL"
		rc="$?"
		if [ "$rc" -ne 0 ]; then
			return "$rc"
		fi

		expected_ip="$(trim_text "$HTTP_BODY")"
		if [ -z "$expected_ip" ]; then
			return 3
		fi

		EXPECTED_IP_SOURCE="url"
		printf '%s\n' "$expected_ip"
		return 0
	fi

	expected_ip="$(trim_text "${PUBLIC_IP:-}")"
	if [ -z "$expected_ip" ]; then
		return 4
	fi

	EXPECTED_IP_SOURCE="env"
	printf '%s\n' "$expected_ip"
	return 0
}
