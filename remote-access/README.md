# Remote access: how friends reach your Jellyfin server

Goal: a far-away friend gets from "here is a link" to "watching with everyone" with as few steps as possible, and nothing about your home network is left open to the whole internet.

This folder covers only the network path (friend -> your PC). Installing Jellyfin, the debrid mount and the SyncPlay cheat sheet live in the other parts of this repo.

## The pick (default): Tailscale

| | Tailscale (default) | Caddy reverse proxy (alternative) |
|---|---|---|
| What friends do | Install the Tailscale app, sign in, click your invite link, then type the address into the Jellyfin player. One time, about 5 minutes. | Open a link. Nothing else. |
| What you do | One script, one invite link per friend. No router changes. | Domain or free DuckDNS name, router port-forward, firewall rule, keep it patched. |
| Exposure | Private. Only people you invited can even see the server. | Jellyfin is on the public internet. Bots will find it. |
| Works behind CGNAT / bad ISP routers | Yes | No (needs an inbound port) |
| Works on any TV or console | No (needs a Tailscale app on the device) | Yes (any Jellyfin client) |
| Cost | Free (Personal plan) | Free (DuckDNS) or a few dollars a year (domain) |

Why Tailscale is the default, in one breath: Caddy is lowest friction for friends, but it puts Jellyfin on the open internet from the same PC you game on, and it fails outright if your ISP uses CGNAT. The friend-side cost of Tailscale is a one-time app install, which is the same size of ask as installing mpv.

Switch to Caddy if: two or more friends refuse or fail the Tailscale step, or they mostly watch on a TV box that cannot run Tailscale (Roku and similar; check the specific device). The two options can run side by side.

Not chosen:
- Tailscale Funnel (public URL, no friend install): Tailscale documents Funnel traffic as subject to non-configurable bandwidth limits, and community reports show video stalling around 1 Mbps [Secondary]. Not suitable for movies.
- Cloudflare Tunnel: Cloudflare restricts serving non-cached video through its proxy, and the rules are unclear. Risk of account suspension [Secondary, from earlier research].

## Quick start (Tailscale)

Host (you), once:
1. Install Jellyfin and confirm `http://localhost:8096` works.
2. In an admin PowerShell: `powershell -ExecutionPolicy Bypass -File remote-access\tailscale\setup-host.ps1`
3. In the Tailscale admin console: disable key expiry for the PC, then Share it and copy an invite link per friend. Details in [tailscale/README.md](tailscale/README.md).
4. Create a Jellyfin user per friend.
5. Create each friend's account and invite message with `friends/New-FriendAccount.ps1` (pass it the Tailscale invite link and the URL the script printed).

Before each movie night: `remote-access\tailscale\check-access.ps1` (optional, 5 seconds).

Friends: [FRIEND-GUIDE.md](FRIEND-GUIDE.md) covers the Tailscale part and hands off to the main guide in `friends/` (player install, login, SyncPlay).

## Files

| File | What it is |
|---|---|
| [FRIEND-GUIDE.md](FRIEND-GUIDE.md) | The Tailscale connection steps for friends, then a hand-off to `friends/FRIEND-GUIDE.md` |
| [tailscale/README.md](tailscale/README.md) | Host walkthrough, what the script does, troubleshooting |
| [tailscale/setup-host.ps1](tailscale/setup-host.ps1) | One-time host setup (installs, signs in, publishes Jellyfin over HTTPS on the tailnet) |
| [tailscale/check-access.ps1](tailscale/check-access.ps1) | Read-only health check, shows if a friend is on a slow relayed path |
| [caddy/README.md](caddy/README.md) | The "just a URL" alternative, with its risks and hardening checklist |
| [caddy/Caddyfile](caddy/Caddyfile) | Minimal reverse proxy config, driven by environment variables |

## Testing status

- Caddyfile: validated with Caddy 2.8.4 (`caddy validate`).
- PowerShell scripts and the Tailscale flow: written but NOT yet run on Windows. They need a pass on a Windows machine with a second Tailscale account playing the friend. Checklist at the bottom of [tailscale/README.md](tailscale/README.md).

## Linking this from the main README

Suggested section for the repo README (kept here so this folder owns its own content):

```markdown
## Remote access for friends

Friends connect over Tailscale (private, free, one-time app install) or, as an
alternative, a Caddy reverse proxy. See [remote-access/](remote-access/README.md).
```

## Open items for other parts of the repo

- The Jellyfin stack should leave Jellyfin listening on port 8096 on the host (default). The scripts here assume `127.0.0.1:8096`.
- The `friends/` folder owns the Jellyfin client (Jellyfin Media Player), the invite message and the SyncPlay cheat sheet. FRIEND-GUIDE.md here only covers the Tailscale connection and links there.
