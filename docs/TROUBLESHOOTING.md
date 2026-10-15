# Troubleshooting

Run `ppg doctor` first. It names the problem and the fix for most of these.

| Symptom | Cause | Fix |
|---|---|---|
| Drive `Z:` never appears | WinFsp just installed and needs a reboot, or zurg started in another session | Reboot once, sign in, run `ppg start`. Never start zurg from a service or over SSH. |
| `Drive Z: is already in use` | Another device uses the letter | Set `MountDrive` in `config\ppg.config.psd1`, then `ppg install` again |
| zurg log: `symlinks not supported without the --links flag` | The `--links` argument was removed from the zurg config | Restore it under `rclone_extra_args` (see `config\zurg.config.yml.template`) |
| zurg starts, library empty | Wrong or expired token, or nothing in your Real-Debrid library yet | `ppg install -RdToken <token>`; add a movie on real-debrid.com |
| `Failed to get user information` loops in the zurg log | Bad token | Same as above |
| Jellyfin libraries show as offline after boot | Jellyfin started before the mount | `ppg start` waits for the mount; if it still happens, `ppg stop` then `ppg start` |
| Doctor: "Jellyfin runs as a Windows service" | Installed with the service option | Uninstall Jellyfin from Settings > Apps, then `ppg install` |
| Doctor: NVENC test encode fails | Old driver, or all NVENC sessions in use by another app | Update the NVIDIA driver; close OBS or other encoders and retry |
| Doctor: driver too old | RTX 50 cards need driver 570 or newer; Jellyfin 12 needs 522.25 or newer | Update from nvidia.com |
| Movie shows up as the wrong film | Torrent name did not parse | In Jellyfin: identify the item, or pick a cleaner release |
| New movie not in Jellyfin | Scan has not run | `ppg scan` |
| SyncPlay drifts for one friend | That friend is transcoding | `ppg status` shows `Transcode` next to their name. Use a smaller release, raise the bitrate cap, or have them use the desktop client |
| Friends buffer | Upload is saturated | Lower `RemoteBitrateLimitMbps`, `ppg bootstrap` |
| Everything stopped after the PC slept | Windows sleep | Settings > System > Power: Sleep (plugged in) = Never |

Logs: zurg in `C:\PPG\zurg\logs`, Jellyfin from its tray icon (Open Log Folder), scan hook errors in `C:\PPG\logs\hook.log`.
