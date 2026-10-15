# Extending the host stack

For the remote access and friend onboarding features (and anything later). The rule: add files, do not edit shared ones, so features never collide.

## Add a command

Create `scripts/commands/<name>.ps1`. The first line must be a comment in this form, it becomes the help text:

```powershell
# ppg invite: create a friend account and print the invite
param([string]$Name)
. (Join-Path $PSScriptRoot '../lib/common.ps1')
. (Join-Path $PSScriptRoot '../lib/jellyfin.ps1')
$cfg = Get-PpgConfig
$state = Get-PpgState -Config $cfg
Connect-Jellyfin -Url $cfg.JellyfinUrl -Token $state.ApiKey
```

Then `ppg invite -Name Sam` works. Options are passed as `-Name value` or `-Flag`.

## Add a setup step

Drop `hooks/post-bootstrap.d/NN-name.ps1` (see its README for the number ranges and the `-Context` shape). Hooks run after every `ppg install` and `ppg bootstrap`, so make them safe to repeat.

## Read settings

`Get-PpgConfig` returns the defaults merged with `config\ppg.config.psd1`. Put feature settings under your own key (`Remote`, `Friends`) so the host stack never reads or overwrites them. Do not put secrets in that file; store them under `C:\PPG\state` with `Save-PpgState` (it limits access to your Windows user).

## Talk to Jellyfin

`Connect-Jellyfin -Url -Token` then `Invoke-Jf -Method POST -Path '/Users/New' -Body @{...}`. Bodies are objects or JSON strings; arrays come back as separate items (wrap in `@()` when you need a list). The full API is at https://api.jellyfin.org. Useful facts for the onboarding feature:

- A new user's `Policy.SyncPlayAccess` is `CreateAndJoinGroups`; set it to `JoinGroups` to stop a friend creating groups.
- `RemoteClientBitrateLimit` on a user policy overrides the server cap for that person.
- Quick Connect is on, so a friend on a TV can log in with a short code.

## Where the host listens

Jellyfin listens on port 8096 on all interfaces. Remote access (Tailscale, tunnel, reverse proxy, firewall rule) is the other feature's job; this one only guarantees the server is healthy and `JellyfinUrl` is the address as seen from this PC. zurg listens on `127.0.0.1:9999` and must stay that way.

## Tests

`tests/test-bootstrap.ps1` runs the bootstrap twice against a throwaway Jellyfin and checks the settings. If your feature changes server settings, add checks there and run it locally:

```powershell
docker run -d --name jf -p 8096:8096 -v ${PWD}/media:/media jellyfin/jellyfin:12.2
pwsh tests/test-bootstrap.ps1 -Url http://localhost:8096 -LibraryRoot /media
```

Run `pwsh tests/lint.ps1` before pushing: scripts must work on Windows PowerShell 5.1, which has no `??`, no ternary, no `&&`, and a one-argument `Join-Path`.
