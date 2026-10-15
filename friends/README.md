# Friend onboarding

Goal (Zach, 2026-10-15): friends install one app, log in once, and then movie night is "open it, join the group, watch". No Syncplay fiddling, no own media, no settings.

This folder is the friend side of the Jellyfin plan. The server stack and remote access live elsewhere in the repo.

## TL;DR

1. Friends use **Jellyfin Media Player 1.12.0** (the official desktop app, mpv inside, SyncPlay built in). Browser is the fallback.
2. You run one script per friend. It creates the account with safe defaults and prints a paste-ready invite.
3. Friends follow the invite (about 5 minutes, once). On movie night they click one icon to join your group.
4. TVs are not supported for synced nights yet.

## Host flow

```powershell
# once per friend, on the PC that runs Jellyfin
$env:JELLYFIN_PUBLIC_URL = 'https://<your-pc>.<tailnet>.ts.net'   # what friends type
.\friends\New-FriendAccount.ps1 -Name Sam -InviteLink '<tailscale invite link for Sam>'
```

The script asks for your Jellyfin admin login (or reads `JELLYFIN_API_KEY`), creates `Sam`, applies the defaults below, logs in as Sam to prove it works, and copies the invite message to your clipboard. Paste it into Discord. The password is shown once and is not stored anywhere.

Useful switches:

| Switch | What it does |
|---|---|
| `-Name A,B,C` | Several friends in one run (no clipboard copy then; copy each from the screen) |
| `-InviteLink l1,l2` | One Tailscale invite link per name. Leave out if friends do not use Tailscale |
| `-Library Movies` | Friends see only these libraries (default: all, including future ones) |
| `-MaxBitrateMbps 20` | Cap per-friend bitrate. Default is no cap so Direct Play stays possible |
| `-AllowCreateGroups` | Let this friend start SyncPlay groups (default: join only) |
| `-ResetPassword` | New password for an existing friend, with a fresh invite |
| `-WhatIf` | Show what would happen, change nothing |

Running it again for an existing friend re-applies the defaults and leaves the password alone.

On movie night, follow the host section of [SYNCPLAY-CHEATSHEET.md](SYNCPLAY-CHEATSHEET.md).

## What friends get

| File | Use |
|---|---|
| [invite-template.txt](invite-template.txt) | The Discord message (1.2k characters, under the 2000 limit). Edit the wording here, tokens are `{USER}`, `{PASSWORD}`, `{URL}`, `{INVITE_LINK}`. The `[[tailscale]]` block is dropped when no invite link is given |
| [FRIEND-GUIDE.md](FRIEND-GUIDE.md) | One-page reference with fixes, for friends who ask. Short enough to paste in two messages |
| [SYNCPLAY-CHEATSHEET.md](SYNCPLAY-CHEATSHEET.md) | Friend lines to paste, plus the host runbook |

If you ever switch from Tailscale to the Caddy route in [remote-access/](../remote-access/README.md), delete step 1 from FRIEND-GUIDE.md and run the script without `-InviteLink`.

## Why this player

| Option | Friend steps | HDR on an ordinary screen | SyncPlay | Verdict |
|---|---|---|---|---|
| **Jellyfin Media Player 1.12.0** | Install, type address, log in | mpv tone-maps locally. Always HDR to SDR, it has no HDR output [Secondary: Jellyfin forum] | Yes, the web UI inside the app | **Pick** |
| Browser (Chrome, Edge) | Open address, log in | Server transcodes and tone-maps (your RTX 5080) unless the browser can play the file as is | Yes, tested | Fallback |
| Jellyfin Desktop 2.0 | Same as JMP | Same engine | Same | Still a pre-release, and it does not migrate settings. Revisit when it is stable |
| Jellyfin MPV Shim | Install, configure, then cast from a second window | Best (real HDR output possible) | Yes, but the project calls it "fragile" | More steps, more fiddling. Only for a friend with an HDR display who wants to |
| Android TV, Fire TV, Roku, other TV apps | Install app | Server transcode | No confirmed support [from the SyncPlay research thread] | Not for synced nights |
| Syncplay + mpv | Two apps, own file | Best | Yes | Rejected by Zach (too much fiddling, needs own media) |

Evidence behind the pick:

- JMP 1.12.0 is the latest stable release. 2.0.0 is marked pre-release and the GitHub "latest" link still points at 1.12.0 [Primary: jellyfin-desktop releases page].
- The installer is on winget as `Jellyfin.JellyfinMediaPlayer`, and the Windows file `JellyfinMediaPlayer-1.12.0-windows-x64.exe` exists [Secondary: wingetly, plus a direct download check].
- Defaults to rely on, from JMP 1.12.0 `settings_description.json` [Primary]: hardware decoding `copy`, no forced transcodes except Dolby Vision (`force_transcode_dovi` is true), `sync_mode` audio. Nothing needs changing for friends.
- Reported SyncPlay trouble with the desktop app is on Jellyfin issue 16241 (open, opened 2026-02). See the "Not tested" list below.

### Why there is no preconfigured installer or config bundle

Looked at it, not built, because it would not remove a friend step:

- The server address is stored inside the app's own web profile, not in a file we can ship. Friends still type it once.
- JMP's defaults are already right (see above), so a config file would only change settings we do not need to change.
- A `.cmd` or `.ps1` that runs winget is one click, but a file downloaded from Discord triggers Windows SmartScreen warnings, which is worse than pasting one line into PowerShell. The invite already hands friends that line.

If Windows testing finds a setting friends must change, add it here as a documented config file and revisit.

## What the account script sets

| Setting | Value | Why |
|---|---|---|
| Administrator | off | Friends never need it |
| Hidden from the login screen | on | Friends do not see each other's names |
| Delete, download, media conversion, public sharing | off | Safe defaults |
| Live TV | off | Not used |
| SyncPlay access | `JoinGroups` (or `CreateAndJoinGroups` with `-AllowCreateGroups`) | One group per night, yours |
| Video and audio transcoding | allowed | Safety net for the browser, Dolby Vision and weak links |
| Remuxing (Direct Stream) | allowed | Cheap and avoids full transcodes |
| Bitrate cap | none (or `-MaxBitrateMbps`) | Favors Direct Play, which SyncPlay likes |
| Failed logins before lockout | 5 | Friends mistype generated passwords; the server still locks out guessing |
| Audio language | `eng` | |
| Subtitles | language `eng`, mode Smart | Subtitles appear only when the film is not in English |
| Next-episode autoplay | off | Movie nights |
| Library access | all, or the ones in `-Library` | |
| Password | 4 random words, for example `puzzle-olive-fiddle-sketch` | Easy to type, about 32 bits, shown once |

Verified on Jellyfin 12.2.0: every value above reads back from the server after the script runs. The script re-reads the policy and configuration from the server and sends the full object back, so settings it does not touch (including new ones in later versions) are preserved.

## Picking a movie that Direct Plays

SyncPlay behaves best when every viewer plays the file as is. The research thread confirmed this for Jellyfin 12.1 and later on desktop and web clients.

- Video: H.264 or HEVC. HDR10 is fine: friends' players tone-map it locally, so it costs your server nothing.
- Avoid Dolby Vision (especially profile 5). JMP forces a server transcode for it by default, which needs your GPU and can add drift. Pick the HDR10 version of the release.
- Audio: JMP's default is stereo output, so a 5.1 track likely gets an audio-only transcode on your server (video still passes through) [Inference from the `audio.channels` default; confirm on Windows]. Cheap, but it is not strictly Direct Play.
- Upload speed is the real limit. Direct Play of a 4K remux is 50 to 80 Mbps per friend [Secondary]. If your upload cannot carry (friends x file bitrate), pick a smaller release or set `-MaxBitrateMbps` to about 80 percent of your upload divided by the number of friends. A cap forces a transcode for any bigger file. This is the open question about Zach's upload speed.

## Testing status

Tested against a real Jellyfin 12.2.0 server (Linux build) with PowerShell 7.4.6:

- Create friend, re-run for an existing friend, `-ResetPassword`, `-WhatIf`, bad library name, bad username, server down, no invite link, bitrate cap, `-AllowCreateGroups`.
- Friend self-check: logs in, sees the right library, `/SyncPlay/List` is allowed.
- SyncPlay in headless Chromium against that server, with an admin host and a join-only friend: join-only friend gets "Permission required to create a group" before the group exists, sees "admin's group" afterwards, playback starts on its own on the friend's screen, pause, resume and seek by either person move both, a late joiner drops in at the group position.
- Found: **leave group then rejoin mid-movie breaks sync** (group pauses, the friend's player does not catch up). The host closing the player and pressing Resume again fixes it. Both docs say so.

Not tested (needs a Windows machine, coordinator to queue):

1. `winget install Jellyfin.JellyfinMediaPlayer` on a clean Windows 11 and 10.
2. JMP 1.12.0 connecting to a Jellyfin 12.x server. JMP bundles an older web client, so run the SyncPlay checks above again inside JMP (people icon location, join, auto start, pause and seek, late join, leave and rejoin).
3. Windows PowerShell 5.1 (the script avoids PowerShell 7 only syntax, but it has only been run on 7.4.6), including the interactive admin prompt when no API key is set.
4. HDR10 and Dolby Vision files on an SDR display and on an HDR display; confirm the picture is not washed out and whether a Dolby Vision file really triggers the server transcode.
5. A second Windows PC as a friend over Tailscale, with a real invite, from the invite text alone, timing the setup.
6. `-MaxBitrateMbps` behavior for a client coming in over Tailscale (whether the server treats it as remote and applies the cap).

## Open items for other parts of the repo

- Stack thread: friends assume Jellyfin 12.x. Keep the server on a version that JMP 1.12.0 can talk to, and note the version in the stack README.
- Remote access thread: `remote-access/FRIEND-GUIDE.md` ends with "open the address in your browser". With this kit the address goes into the player. Suggest trimming it to the Tailscale steps, or pointing at the invite text here.
- Repo README: add a "Friends" section linking to this folder.
