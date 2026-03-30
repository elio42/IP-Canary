# IP-Canary
A docker container used to detect if a docker-network behind a VPN leaks your personal public IP. E.g. due to configuration errors.

There are two modes to use this container: `watchdog` and `ip_provider`. The container in `watchdog` mode is the one that should be behind your VPN

If an IP leak is detected the conainers health will be set to `unhealthy`. If you want to send yourself message if an IP leak is detected, you can use [Gotify](https://github.com/gotify/server). Therefore you should have a running Gotify instance.

## Modes

### watchdog
Run this mode inside the VPN-protected Docker network. If the watchdog recognises that your public ip inside the VPN-protected network is also your actual public ip, it will send and alert to you.

**Parameters:**

| Parameter | Function | Mandatory |
|---|---|---|
| MODE=watchdog | Sets the mode of the container<br>Must be: `watchdog` or `ip_provider` | Yes |
| CHECK_INTERVAL= | Defines how many seconds between checks.<br>Default value: 60 seconds | No |
| MESSAGE_REPEAT_MINUTES= | Defines how long until the container will send a new message if an issue persists in minutes.<br>Default value: 30 minutes | No |
| USE_GOTIFY= | Bool, must be `true` or `false`<br>Default: true | No |
| GOTIFY_URL= | Point to the IP and port of your Gotify server.<br>E.g. `172.0.0.1:80` | Yes* |
| GOTIFY_API_KEY= | **Application** key from your Gotify web-interface. | Yes* |
| PUBLIC_IP= | Here you can manually set your own public IP. Useful if you have a static IP. | Yes** |
| REAL_IP_URL= | Point to instance of this container in `ip_provider` mode.<br>Must include full URL, e.g.: `http://172.0.0.1:9516/public-ip` | Yes** |
| PROVIDER_FAILURE_TOLERANCE= | How often the `ip_provider` is allowed to fail before sending a message. ***<br>Default value: `3` | No |

- \* Mandatory if you use Gotify for messaging. Irrelvant if `USE_GOTIFY=false`.
- \*\* **EITHER** `PUBLIC_IP` **OR** `REAL_IP_URL` must be set. If both are set the value from the ip_service is prefered.
- \*\*\* The reason for a `PROVIDER_FAILURE_TOLERANCE` is because statistically every now and then getting the public ip will fail. If you have a very long intervall between ip-checks (e.g. 10 minutes) you might want to lower the tolerance to make sure it doesn't take too long until you are notified after an IP-leak.

**Example Compose:**

This is an example how your compose migth look like. If you know what you are doing you can of course also manually create a docker network and have the _ip-canary_, your _vpn_ and the _service you want to hide_ in separate compose files.

```yml
services:
  watchdog:
    image: "ip-canary:latest"
    container_name: "ip-canary-watchdog"
    network_mode: "service:vpn"
    restart: unless-stopped
    environment:
      - MODE=watchdog
      - REAL_IP_URL=http://172.0.0.1:9516/public-ip
      - GOTIFY_URL=--- # eg. //172.0.0.1:80
    depends_on:
      - vpn

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
      - vpn
```

Notice that I use `network_mode: "service:vpn"` here to make sure that my service I want to hide and the ip-canary are actually in the vpn network.

> [!CAUTION]
> Just make sure that the network settings of the ip-canary and the service you want to protect are the **same**. Otherwise you might still leak your ip without noticing.

### ip_provider
Run the the container in this mode outside the VPN-protected network.

**Parameters:**

| Parameter | Function | Mandatory |
|---|---|---|
| MODE=ip_provider | Sets the mode of the container<br>Must be: `watchdog` or `ip_provider` | Yes |
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

## Gotify Behavior

- Startup test: when USE_GOTIFY=true, a test message is sent at startup.
- If startup test response is not HTTP 200, container startup fails and exits.
- Runtime alerts: both leak and provider-failure warnings use repeat cooldown based on MESSAGE_REPEAT_MINUTES.
- Payload includes title and message only. No priority field is sent, you can set the priority in the web-ui of Gotify
- If Gotify fails to send a message the container will be set to unhealthy.

## Healthcheck Behavior

- Container process is not terminated on runtime HTTP errors.
- Instead, runtime failures mark internal health state as unhealthy.
- Docker HEALTHCHECK reads that state and reports the container unhealthy.
- On successful later checks, health state returns to healthy.
