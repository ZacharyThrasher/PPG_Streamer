# PPG Movie Streamer

Movie nights with friends who live far away. Zach's Windows PC hosts the movie once. Friends watch their own stream in sync. No screen sharing, no friend-side media, almost no setup for them.

This repo is built in features, one per branch. This README covers the host stack (Jellyfin plus the debrid mount). Remote access and friend onboarding are separate features that plug in through the hooks described below.

## What you get

| Piece | Choice | Why |
|---|---|---|
| Media server | Jellyfin 12.2 or newer, installed natively on Windows | SyncPlay built in, NVENC and CUDA tone mapping built in, nothing for friends to host |
| Debrid mount | zurg (free edition) with its built-in rclone, mounted as drive `Z:` | One Real-Debrid account, only this PC ever talks to Real-Debrid |
| Playback path | Direct Play first | Best picture, no server load, SyncPlay stays in sync |
| Fallback | NVENC transcode with CUDA HDR to SDR tone mapping on the RTX 5080 | For browsers and weak devices |
| Library scans | Triggered by changes, thumbnails and chapter images off | Does not hammer the debrid account |

Why these picks, with pros, cons and risks: [docs/DECISIONS.md](docs/DECISIONS.md).

## Set it up (about 10 minutes)

You need: the Windows PC, a current NVIDIA driver, a Real-Debrid premium account.

1. Get your Real-Debrid API token: https://real-debrid.com/apitoken
2. Open PowerShell in this folder and run:

   ```powershell
   .\ppg.cmd install
   ```

3. Paste the token when asked. It is stored outside the repo and never printed.
4. When it finishes, run the health check:

   ```powershell
   .\ppg.cmd doctor
   ```

The installer asks Windows for permission when it installs WinFsp and Jellyfin. If Jellyfin's own installer shows an "install as service" option, leave it off (a service cannot see the debrid drive).

## Every day

| Command | What it does |
|---|---|
| `ppg doctor` | Checks GPU, NVENC, tone mapping, mount, settings. Says how to fix each problem. |
| `ppg status` | What is running, library counts, who is watching and whether it is Direct Play or a transcode |
| `ppg scan` | Look for newly added movies and shows now |
| `ppg start` / `ppg stop` | Start or stop the mount and Jellyfin (they start by themselves when you sign in) |
| `ppg bootstrap` | Re-apply all settings (safe to repeat; run after editing `config\ppg.config.psd1`) |
| `ppg uninstall` | Stop and remove the start-at-logon entry |

Use `.\ppg.cmd <command>` from PowerShell, or `ppg <command>` from this folder in cmd.

## Adding movies

Add the movie to your Real-Debrid library (Debrid Media Manager or the Real-Debrid site). zurg shows it under `Z:\movies` within seconds and tells Jellyfin to scan about a minute later. `ppg scan` forces it.

Pick releases friends can Direct Play. A 4K remux is 50 to 80 Mbps, which most home upload links cannot send to several people. A 1080p release at 10 to 25 Mbps is what movie night should use. See the bitrate table below.

## Remote bitrate cap

Set `RemoteBitrateLimitMbps` in `config\ppg.config.psd1` (copy from `config\ppg.config.example.psd1`), then run `ppg bootstrap`. Default is 0 (no cap).

Rule: `cap = (upload speed in Mbps x 0.8) / friends watching`.

| Home upload | 4 friends | 6 friends |
|---|---|---|
| 100 Mbps | 20 | 13 |
| 300 Mbps | 60 | 40 |
| 1000 Mbps | 200 (no cap needed) | 133 (no cap needed) |

A friend whose movie is above the cap gets a GPU transcode instead of Direct Play. That works, but SyncPlay is most reliable when everyone Direct Plays, so prefer smaller releases over a low cap.

## How other features plug in

| Hook | Where | Used for |
|---|---|---|
| Post-bootstrap scripts | `hooks\post-bootstrap.d\NN-name.ps1`, see [its README](hooks/post-bootstrap.d/README.md) | Remote access (10-19), friend onboarding (20-29), pre-flight (30-39) |
| New commands | drop `scripts\commands\<name>.ps1`; `ppg <name>` finds it | `ppg invite`, `ppg preflight`, and so on |
| Settings | `Remote = @{}` and `Friends = @{}` in `ppg.config.psd1` | Each feature reads its own section |
| Jellyfin API helpers | `scripts\lib\jellyfin.ps1`: `Connect-Jellyfin`, `Invoke-Jf` | Create friend accounts, set SyncPlay access, and so on |
| Admin API key | saved in `C:\PPG\state\state.json` (your user only) | Same helpers read it |

More: [docs/EXTENDING.md](docs/EXTENDING.md).

## Layout

```
ppg.cmd / ppg.ps1          entry point
scripts/commands/          one file per ppg command
scripts/lib/               shared code (config, Jellyfin API, Windows host helpers)
scripts/zurg-library-hook.ps1   zurg calls this when your debrid library changes
config/                    settings example and the zurg config template
hooks/post-bootstrap.d/    where other features add their setup steps
tests/                     lint, and a bootstrap test run against a real Jellyfin in CI
docs/                      decisions, troubleshooting, Windows test plan
```

Everything machine-specific lives in `C:\PPG` (zurg, logs, saved state), outside the repo.

## Status and known gaps

- The Jellyfin settings code is tested in CI against a real Jellyfin 12.2 server (all settings read back through the API).
- The Windows parts (winget installs, WinFsp, the zurg mount, NVENC encode, start at logon) have not run on a real Windows PC yet. [docs/WINDOWS-TEST-PLAN.md](docs/WINDOWS-TEST-PLAN.md) lists exactly what to check.
- Not verified yet: how many simultaneous NVENC transcodes the RTX 5080 holds before sessions fail, and Real-Debrid behaviour under several friends at once through one server. The test plan measures both.
