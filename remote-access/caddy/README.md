# Caddy reverse proxy (the "just a URL" option)

Friends open `https://movies.yourname.duckdns.org`. No app, no account except their Jellyfin login. Works on any device with a Jellyfin client, including TVs.

The price: **Jellyfin is on the public internet, on the PC you also use for everything else.** Read the risks before choosing this.

## Use this if

- Tailscale is not working out for several friends, or
- friends mostly watch on TVs that cannot run Tailscale, and
- your ISP gives you a real public IP (see step 1 below).

## Risks (read these)

| Risk | Why it matters | Mitigation |
|---|---|---|
| Public attack surface | Bots scan the whole internet for Jellyfin. A bug in Jellyfin becomes a bug on the internet. | Keep Jellyfin updated, no public sign-up, strong unique passwords, admin account not used for watching. |
| Home IP is public | Your IP address is reachable and visible in DNS. | Accept it, or use Tailscale instead. |
| Your main PC is the server | Compromise of Jellyfin means a foothold next to your files and accounts. | Run Jellyfin as a normal service, not elevated. Consider moving to a dedicated box later. |
| ISP rules | Some residential ISPs forbid running servers. | Check your terms. |
| Upload saturation | Everyone streams from your upload at once. | Set an internet streaming bitrate limit in Jellyfin. |

## Setup

### 1. Check you can accept inbound connections

Compare your router's WAN IP (router admin page) with what https://ifconfig.me shows. If they differ, or the WAN IP starts with `100.64` to `100.127`, you are behind CGNAT. Port forwarding cannot work. Use Tailscale instead, or ask your ISP for a public IP.

### 2. Get a name

Easiest free option: DuckDNS. Make a subdomain at https://www.duckdns.org (for example `ppgmovies.duckdns.org`). Or use your own domain with an A record pointing at your public IP.

Home IPs change. Keep DuckDNS updated with a Scheduled Task that runs every 5 minutes. Save this as `C:\Scripts\duckdns.ps1` (keep the token in a user environment variable named `DUCKDNS_TOKEN`, not in the file):

```powershell
$u = "https://www.duckdns.org/update?domains=ppgmovies&token=$($env:DUCKDNS_TOKEN)&ip="
Invoke-WebRequest -UseBasicParsing -Uri $u | Out-Null
```

Then register the task:

```powershell
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\Scripts\duckdns.ps1'
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 9999)
Register-ScheduledTask -TaskName 'DuckDNS update' -Action $action -Trigger $trigger
```

### 3. Forward two ports on your router

| External | Internal | Where |
|---|---|---|
| TCP 443 | your PC, 443 | Caddy serves HTTPS |
| TCP 80 | your PC, 80 | Caddy uses this to get and renew the certificate |

Give the PC a fixed local IP (DHCP reservation) first. Do **not** forward 8096. Jellyfin itself stays private; only Caddy is exposed.

### 4. Allow Caddy through Windows Firewall

Admin PowerShell:

```powershell
New-NetFirewallRule -DisplayName 'Caddy HTTP/HTTPS' -Direction Inbound -Protocol TCP -LocalPort 80,443 -Action Allow -Profile Any
```

### 5. Install and run Caddy

```powershell
winget install --id CaddyServer.Caddy -e
$env:JELLYFIN_DOMAIN = 'ppgmovies.duckdns.org'
caddy run --config remote-access\caddy\Caddyfile
```

Caddy gets a Let's Encrypt certificate on first start. To keep it running across reboots, install it as a Windows service (see the Caddy docs for Windows services) or use a Scheduled Task that runs at startup with the same environment variable set.

### 6. Tell Jellyfin about the proxy

Dashboard -> Networking -> **Known proxies**: add `127.0.0.1`. Without it Jellyfin sees every friend as coming from your own PC, and treats them as "local", which skips the remote bitrate limit.

Also set the **Internet streaming bitrate limit** (Dashboard -> Playback -> Streaming).

### 7. Lock it down

- [ ] Public sign-up is off (Jellyfin has none by default; do not add a plugin that enables it).
- [ ] Every friend has their own user and a unique password.
- [ ] Your admin account is not one of the viewing accounts.
- [ ] Jellyfin is on the latest stable release; recheck monthly.
- [ ] Only ports 80 and 443 are forwarded.
- [ ] Test from outside your network (phone on mobile data) before telling anyone.

## Config notes

- The Caddyfile is driven by two environment variables: `JELLYFIN_DOMAIN` (required) and `JELLYFIN_UPSTREAM` (default `127.0.0.1:8096`).
- Validated with Caddy 2.8.4 (`caddy validate`). Not yet run end to end on Windows with a real domain.
- Caddy docs: https://caddyserver.com/docs/
- Jellyfin's own reverse proxy notes: https://jellyfin.org/docs/general/post-install/networking/reverse-proxy/caddy/

## Switching back

Remove the two router forwards and stop Caddy. Nothing else changes; the Tailscale option keeps working.
