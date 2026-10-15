# post-bootstrap hooks

Any `*.ps1` file in this folder runs, in file-name order, at the end of `ppg install` and `ppg bootstrap`, after Jellyfin is configured and the admin API key exists.

Other features (remote access, friend onboarding, pre-flight checks) add their own numbered file here instead of editing shared scripts, so features never collide:

| Number range | Used by |
|---|---|
| 10-19 | remote access (Tailscale, reverse proxy, firewall) |
| 20-29 | friend onboarding (accounts, SyncPlay permissions, invite pages) |
| 30-39 | pre-flight and monitoring |

A hook receives one parameter, `-Context`, a hashtable:

| Key | Meaning |
|---|---|
| `Config` | merged settings (defaults plus `config\ppg.config.psd1`), including `Config.Remote` and `Config.Friends` for the feature's own settings |
| `Url` | Jellyfin address as seen from this PC |
| `ApiKey` | admin API key for Jellyfin |
| `Version` | Jellyfin version |

Minimal hook:

```powershell
# hooks/post-bootstrap.d/20-friends.ps1
param([hashtable]$Context)
. (Join-Path $Context.Config.Root 'scripts/lib/common.ps1')
. (Join-Path $Context.Config.Root 'scripts/lib/jellyfin.ps1')
Connect-Jellyfin -Url $Context.Url -Token $Context.ApiKey
$users = Invoke-Jf -Path '/Users'
```

A failing hook prints a warning and does not stop the others. Hooks must be safe to run repeatedly.
