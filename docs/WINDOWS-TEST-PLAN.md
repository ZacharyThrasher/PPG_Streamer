# Windows test plan (host stack)

For the Windows test machines. Everything here is unverified on real Windows until ticked. The Jellyfin API half is already tested in CI; this plan covers what CI cannot.

Machine needs: Windows 10 or 11, an NVIDIA GPU (the RTX 5080 PC is the real target), a Real-Debrid premium account with at least one 4K HDR movie and one 1080p movie in the library, a second device for a client.

Record for each step: pass or fail, and the console output or screenshot for fails.

## A. Install (clean machine, no Jellyfin, no WinFsp)

1. Clone the repo. In PowerShell: `.\ppg.cmd install`. Paste the token when asked.
2. Expect: WinFsp installs (UAC prompt), Jellyfin installs (UAC prompt), zurg downloads, drive `Z:` appears, Jellyfin configured, a "PPG Movie Night" shortcut in `shell:startup`.
3. Check that the Jellyfin installer did not install a service (`Get-Service JellyfinServer` should not exist).
4. `ppg doctor` exits 0.
5. Open `Z:\movies` in Explorer: your movies are listed.

Unknowns to confirm here: the winget ids `WinFsp.WinFsp` and `Jellyfin.Server`; that the winget Jellyfin install is silent and creates no service; that zurg fetches `bin\rclone.exe` and `bin\ffprobe.exe` by itself (if not, the installer runs `zurg.exe download-requirements`; note which path was used); that `zurg.exe` host `127.0.0.1` is accepted.

## B. Sign-out and sign-in

6. Restart the PC and sign in. Within two minutes `ppg status` shows zurg, the mount and Jellyfin running, with no window flashing.

## C. Library and scans

7. Add a movie on real-debrid.com. Within about two minutes it appears in Jellyfin without running `ppg scan` (zurg hook). Check `C:\PPG\logs\hook.log` for errors.
8. Run `ppg scan` and confirm it returns immediately.
9. Watch Real-Debrid account activity and the zurg dashboard (http://localhost:9999/config/) during a scan: requests should be a trickle, with no whole-file downloads.

## D. Direct Play and SyncPlay

10. Play the 1080p movie from the Jellyfin desktop client on a second device. `ppg status` shows `DirectPlay`.
11. Two clients, SyncPlay group: pause, seek, resume. Note drift in seconds.

## E. Transcoding and tone mapping (the GPU fallback)

12. Play the 4K HDR movie in a web browser. `ppg status` shows `Transcode`. The picture is correct SDR, not washed out or blown out.
13. While it plays, Task Manager > Performance > GPU shows Video Decode, Video Encode and Cuda engine use, and CPU stays low.
14. Add friends one at a time (extra browser sessions, different movies or the same). Record the number at which transcodes start to fail or stutter (NVENC session limit on RTX 50 is unverified).
15. Set `RemoteBitrateLimitMbps = 8`, run `ppg bootstrap`, play a high-bitrate file from a remote device: it transcodes down to about 8 Mbps.

## F. Failure cases

16. `ppg stop`, confirm the drive disappears and no `zurg`/`rclone`/`jellyfin` processes remain. `ppg start` brings it back.
17. Install Jellyfin as a service on a spare machine and run `ppg install`: it refuses with a clear message.
18. Set a wrong token: `ppg install -RdToken abc` fails with a clear message.
19. Network check: from another PC on the LAN, `http://<host>:9999` must not answer (zurg is loopback only); `http://<host>:8096` does.
20. Let the PC sleep with the default power plan, wake it: note whether the mount recovers by itself or needs `ppg stop` and `ppg start`.
