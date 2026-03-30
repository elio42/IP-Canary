#!/bin/sh

LAST_GOTIFY_STATUS=""

json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; :a;N;$!ba;s/\n/\\n/g'
}

send_gotify_message() {
	title="$1"
	message="$2"

	endpoint="${GOTIFY_URL%/}/message?token=${GOTIFY_API_KEY}"
	payload="{\"title\":\"$(json_escape "$title")\",\"message\":\"$(json_escape "$message")\"}"

	tmp_body="$(mktemp)"
	status="$(curl -sS -L --max-time "${HTTP_TIMEOUT:-10}" -o "$tmp_body" -w "%{http_code}" -H "Content-Type: application/json" -d "$payload" "$endpoint")"
	curl_rc="$?"
	response_body="$(cat "$tmp_body")"
	rm -f "$tmp_body"

	LAST_GOTIFY_STATUS="$status"

	if [ "$curl_rc" -ne 0 ]; then
		printf 'Gotify request failed with curl error.\n' >&2
		return 1
	fi

	if [ "$status" != "200" ]; then
		printf 'Gotify returned HTTP %s: %s\n' "$status" "$response_body" >&2
		return 22
	fi

	return 0
}
