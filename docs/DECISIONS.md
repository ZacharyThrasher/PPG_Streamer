# Decisions for the host stack

Each decision: what was picked, then pros, cons, risks. Sources are the two research files in the project (movie night options, and the Discord watch party review).

## 1. Debrid mount: zurg (free edition) plus its built-in rclone

Picked: zurg-public v1.x, config in `C:\PPG\zurg\config.yml`, mounted as `Z:` with WinFsp.

| | |
|---|---|
| Pros | Runs natively on Windows. Starts and supervises rclone itself, so one process to manage. Auto-downloads rclone and ffprobe. Repairs dead links on access. Calls a hook when the library changes, so Jellyfin scans only when something changed. Needs no Radarr or Sonarr. |
| Cons | Real-Debrid only in the free edition (TorBox and AllDebrid need a sponsorship). A mount exists only in the desktop session that started it, so the PC must be signed in. |
| Risks | zurg is a third-party project; a breaking release is possible. Pin with `ppg install -ZurgVersion v1.0.0` if that happens. Real-Debrid rules on serving friends are not confirmed in writing (see decision 4). |

Not picked: Decypharr (rclone plus a download manager). It supports TorBox and Real-Debrid but wants Radarr/Sonarr to be useful, which is far more to run for a handful of movie nights. Revisit if you move to TorBox.

## 2. Jellyfin: native Windows install, not Docker

| | |
|---|---|
| Pros | NVENC and CUDA tone mapping work with the plain NVIDIA driver. No WSL, no container GPU setup. The mount is a normal drive Jellyfin can see. |
| Cons | Not one-command reproducible like Docker. Updates are manual (re-run the installer). |
| Risks | The Jellyfin installer has a "run as service" option. A service cannot see the mount (Windows sessions), so the installer and doctor refuse it. |

Docker on Windows would need the WSL2 GPU path plus a FUSE mount shared into the container. Possible, fragile, and nothing here needs it. A Linux/Docker version makes sense only if hosting moves to a dedicated box.

## 3. Playback: Direct Play first, NVENC as the fallback

SyncPlay is only solid when everyone Direct Plays on Jellyfin 12.1 or newer. Transcoding viewers can drift by seconds, and several transcode-related SyncPlay bugs are open. So:

- The stack pins Jellyfin 12.2 or newer (`ppg doctor` fails below that).
- Friends should use a client that plays the original file and tone-maps HDR itself (the desktop Jellyfin client uses mpv). That path costs the server nothing.
- NVENC with CUDA HDR to SDR tone mapping is on by default for browsers, weak devices and anyone over the bitrate cap.

| | |
|---|---|
| Pros | Best picture, lowest server load, most reliable sync. Fallback still works for a friend who cannot install anything. |
| Cons | Direct Play of a big remux needs upload bandwidth per friend. |
| Risks | Bandwidth is the real limit, not the GPU. Use the bitrate table in the README and prefer 1080p releases of 10 to 25 Mbps for movie night. |

Transcode settings applied: hardware acceleration NVENC, hardware encode on, HEVC encode allowed, AV1 encode off (fewer surprises across clients), enhanced NVDEC on (needed for Dolby Vision), tone mapping CUDA with the `bt2390` algorithm, throttling and segment deletion on.

## 4. Real-Debrid and friends

Only this server talks to Real-Debrid, from one IP. Friends never get a debrid link or account. zurg listens on `127.0.0.1` only. Real-Debrid wording on serving others through one server has not been checked with them. If that matters, ask them in writing; TorBox is reported to have no IP restriction (unverified).

## 5. What is switched off, and why

| Setting | Why |
|---|---|
| Realtime library monitor | Cannot watch a network-style mount; would poll |
| Trickplay (scrub thumbnails) and chapter images | Read whole files; the research flags this as a way to get a debrid account banned |
| Periodic "Scan Media Library", segment scan, keyframe, audio normalization jobs | Bulk reads. Scans run when zurg reports a change, or with `ppg scan` |
| Saving subtitles or metadata next to the media | The mount is read-only |
| Scan concurrency | Set to 2 so a scan is a trickle of requests, not a burst |

Subtitle extraction stays on because it only runs on demand. A burned-in or extracted subtitle on a remux can read most of the file once; that is normal for one movie, not a scan.

## 6. Start at logon through the Startup folder

A WinFsp mount only exists inside the Windows session that made it. A Windows service or a scheduled task that runs when you are not signed in mounts a drive you cannot see. So the stack starts from the Startup folder when you sign in, with no admin rights. The cost: the PC must be signed in (it can be locked) and awake. `ppg doctor` warns if it is set to sleep.
