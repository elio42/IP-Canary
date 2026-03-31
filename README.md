# IP-Canary
A docker container used to detect if a docker-network behind a VPN leaks your personal public IP. E.g. due to configuration errors.

There are three modes to use this container: `watchdog`, `ip_provider`, and `heartbeat_observer`.
The container in `watchdog` mode is the one that should be behind your VPN.

If an IP leak is detected the container health will be set to `unhealthy`.
If you want to send yourself notifications in the event of an anomaly, you can use [Gotify](https://github.com/gotify/server).

## Modes

### watchdog
Run this mode inside the VPN-protected Docker network. If the watchdog recognises that your measured public IP inside the VPN-protected network matches your  real public IP, it sends an alert to you.

**Parameters:**

| Parameter | Function | Mandatory |
|---|---|---|
| MODE=watchdog | Sets the mode of the container<br>Must be: `watchdog`, `ip_provider`, or `heartbeat_observer` | Yes |
| INSTANCE_NAME= | Name included in all notification messages.<br>Default: container hostname | No |
| CHECK_INTERVAL= | Defines how many seconds between checks.<br>Default value: 60 seconds | No |
| MESSAGE_REPEAT_SECONDS= | Defines how long until the container sends a repeated alert if an issue persists.<br>Default value: 1800 seconds | No |
| USE_GOTIFY= | Bool, must be `true` or `false`<br>Default: true | No |
| GOTIFY_URL= | Point to the IP and port of your Gotify server.<br>E.g. `172.0.0.1:80` | Yes* |
| GOTIFY_API_KEY= | **Application** key from your Gotify web-interface. | Yes* |
| PUBLIC_IP= | Here you can manually set your own public IP. Useful if you have a static IP. | Yes** |
| REAL_IP_URL= | Point to instance of this container in `ip_provider` mode.<br>E.g.: `172.0.0.1:9516/public-ip` | Yes** |
| PROVIDER_FAILURE_TOLERANCE= | Number of consecutive provider-related failures allowed before watchdog health is marked unhealthy and an alert is sent.<br>Default value: `3` | No |

- \* Mandatory if you use Gotify for messaging. Irrelevant if `USE_GOTIFY=false`.
- \*\* **EITHER** `PUBLIC_IP` **OR** `REAL_IP_URL` must be set. If both are set the value from the ip_service is prefered.
- \*\*\* The reason for a `PROVIDER_FAILURE_TOLERANCE` is because statistically every now and then getting the public ip will fail. If you have a very long intervall between ip-checks (e.g. 10 minutes) you might want to lower the tolerance to make sure it doesn't take too long until you are notified after an IP-leak.

**Example Compose:**

This is an example how your compose migth look like. If you know what you are doing you can of course also manually create a docker network and have the _ip-canary_, your _vpn_ and the _service you want to hide_ in separate compose files.

```yml
services:
  watchdog:
    image: "elio11/ip-canary:latest"
    container_name: "ip-canary-watchdog"
    network_mode: "service:vpn"
    restart: unless-stopped
    environment:
      - MODE=watchdog
      - REAL_IP_URL=http://172.0.0.1:9516/public-ip #(for example)
      - GOTIFY_URL=--- # eg. //172.0.0.1:80
      - GOTIFY_API_KEY=---
    volumes:
      - [wherever you want]:/shared-state
    depends_on:
      vpn:
        condition: service_healthy

  #Everything from here out is just a suggestion of how your setup might look.
  vpn:
    image: some/image:lates
    cap_add:
      - NET_ADMIN
    ports:
      - 1234:[protected_service_web-ui_port]
    environment:
      - FIREWALL_OUTBOUND_SUBNETS=xxx.xxx.xxx.0/24 # Internal network

  protected_service:
    image: some/other_image:latest
    restart: unless-stopped
    network_mode: "service:vpn"
    depends_on:
      vpn:
        condition: service_healthy
```

Notice that I use `network_mode: "service:vpn"` here to make sure that my service I want to hide and the ip-canary are actually in the vpn network.

The following makes sure that your containers are only started **after** the vpn is up and running.

```yml
depends_on:
      vpn:
        condition: service_healthy
```

> [!CAUTION]
> Just make sure that the network settings of the ip-canary and the service you want to protect are the **same**. Otherwise you might still leak your ip without noticing.

### ip_provider
Run the container in this mode outside the VPN-protected network.

**Parameters:**

| Parameter | Function | Mandatory |
|---|---|---|
| MODE=ip_provider | Sets the mode of the container<br>Must be: `watchdog`, `ip_provider`, or `heartbeat_observer` | Yes |
| IP_CHECKER_PORT= | Set the port of the endpoint. *<br>Default: `9516` | No |

- \* I would generally suggest just mapping the port to your desired port in the `ports:` section. Like `- "[your desired port]:9516"`

Compose:
```yml
services:
  ip_canary_provider:
    image: "elio11/ip-canary:latest"
    container_name: "ip-canary-provider"
    restart: unless-stopped
    environment:
      - MODE=ip_provider
    ports:
      - "9516:9516"
```

### heartbeat_observer
Run this mode in a separate container to observe a watchdog's shared health and heartbeat files.
The observer sends notifications on:
- startup (always)
- first successfull healthcheck 
- healthy -> unhealthy transition
- unhealthy -> healthy transition

**Parameters:**

| Parameter | Function | Mandatory |
|---|---|---|
| MODE=heartbeat_observer | Enables observer mode. | Yes |
| INSTANCE_NAME= | Name of the observer instance used in notifications.<br>Default: container hostname | No |
| CHECK_INTERVAL= | How often observer checks observed files in seconds.<br>Default: `60` | No |
| HEARTBEAT_STALE_SECONDS= | Maximum allowed age of heartbeat update before considered stale.<br>Default: `360` (6 minutes) | No |
| USE_GOTIFY= | Bool, must be `true` or `false`.<br>Default: `true` | No |
| GOTIFY_URL= | Point to Gotify server. | Yes* |
| GOTIFY_API_KEY= | Gotify application key. | Yes* |

Example observer service:

```yml
services:
  heartbeat_observer:
    image: "elio11/ip-canary:latest"
    container_name: "ip-canary-observer"
    restart: unless-stopped
    environment:
      - MODE=heartbeat_observer
      - GOTIFY_URL=---
      - GOTIFY_API_KEY=---
    volumes:
      - [wherever you want]:/shared-state
```

If watchdog `CHECK_INTERVAL` is higher than 360 seconds, increase `HEARTBEAT_STALE_SECONDS` accordingly.
    Watchdog and observer use fixed internal files at `/shared-state/ip-canary-health` and `/shared-state/ip-canary-heartbeat`, so both services should mount the same shared volume path.

## Gotify Behavior

- All messages include `INSTANCE_NAME` and a fallback to hostname if not configured.
- Watchdog sends a startup status message with expected IP source/value, measured IP, and current errors.
- Runtime watchdog alerts for leak and provider failures use repeat cooldown based on `MESSAGE_REPEAT_SECONDS`.
- Observer sends startup and transition messages only (no periodic heartbeat spam).
- Payload includes title and message only. No priority field is sent.

## Healthcheck Behavior

- Container process is not terminated on runtime provider errors.
- Provider-related errors only mark watchdog unhealthy after `PROVIDER_FAILURE_TOLERANCE` consecutive failures.
- Confirmed leak detection still marks watchdog unhealthy immediately.
- Docker HEALTHCHECK reads `/shared-state/ip-canary-health` and reports healthy/unhealthy accordingly.
