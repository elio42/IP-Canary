# syntax=docker/dockerfile:1

FROM alpine:latest
RUN apk add --no-cache curl busybox-extras

COPY src/ /scripts/
RUN chmod +x /scripts/entry_script.sh \
	/scripts/watchdog/watchdog.sh \
	/scripts/base_ip_provider/ip_provider.sh \
	/scripts/messenger/gotify_messenger.sh \
	/scripts/heartbeat/heartbeat_observer.sh \
	/scripts/ip_provider/ip_provider.sh \
	/scripts/healthcheck.sh \
	/scripts/health/health_state.sh

WORKDIR /scripts
HEALTHCHECK --interval=20s --timeout=10s --start-period=20s --retries=2 CMD ["sh", "/scripts/healthcheck.sh"]
ENTRYPOINT ["sh", "/scripts/entry_script.sh"]