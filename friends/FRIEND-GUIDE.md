# Movie night: your one-page guide

One-time setup takes about 5 minutes. After that, movie night is: open the player, join the group, watch.

Your address, username and password are in the message Zach sent you.

## You need

- A Windows PC, Mac or Linux computer (a laptop is perfect)
- The message from Zach (it has your login and the Tailscale invite link)
- Nothing else. You do not need to own, download or find any movie.

## Set up (once)

1. **Connect.** Install Tailscale from https://tailscale.com/download and sign in with a Google, Microsoft, Apple or GitHub account. Open the invite link from Zach and press Accept.
2. **Install the player.** It is free and called Jellyfin Media Player.
   - Windows: press the Windows key, type PowerShell, open it, paste `winget install Jellyfin.JellyfinMediaPlayer` and press Enter.
   - Mac, Linux, or winget does not work: download it from https://github.com/jellyfin/jellyfin-desktop/releases/latest and pick the file for your computer.
3. **Log in.** Open Jellyfin Media Player. When it asks for a server, type the address from Zach's message, then your username and password.
4. **Leave every setting alone.** The defaults are right.

You do not need to install or configure anything called Syncplay or mpv. The player already has what it needs.

## Every movie night

1. Join the voice call.
2. Open Jellyfin Media Player (make sure Tailscale says Connected).
3. Wait until Zach says the group is ready.
4. Click the people icon in the top right bar and press Zach's group. A message says "SyncPlay enabled".
5. Do nothing else. When Zach presses play, the movie opens and starts on its own, in sync with everyone. Joining late works too: you drop in at the same spot as everyone else.

Full details and fixes are in [SYNCPLAY-CHEATSHEET.md](SYNCPLAY-CHEATSHEET.md).

## Good to know

- Anyone's pause pauses everyone. That is on purpose: use it for a real break and say so on voice.
- Seeking (dragging the bar, skipping ahead) also moves everyone. Leave that to Zach.
- Audio and subtitle choices are yours alone. Change them from the buttons at the bottom of the player.
- Smart TVs and streaming boxes do not work for synced nights yet. Use a laptop, or plug a laptop into the TV with an HDMI cable.
- No Windows PC or the app will not install? Open the same address in Chrome or Edge instead and log in. It works the same way, with slightly lower picture quality.

## If something goes wrong

| What you see | Try this |
|---|---|
| Player cannot reach the server | Open Tailscale and check it says Connected. Then reopen the player. |
| "Permission required to create a group" | Zach has not started the group yet. Wait for him to say it is ready, then try again. |
| The people icon shows no group to join | Same thing: the group does not exist yet. |
| Movie did not start for you after Zach pressed play | Tell Zach on voice. He closes the player and presses play again, and everyone restarts together. Do not leave and rejoin the group by yourself. |
| Everything paused by itself for a few seconds | Someone's connection is catching up. It resumes on its own. Wait. |
| Picture is stuck, black, or you hear nothing | Tell Zach. Zach restarts the movie for the group. If it is only you, close the player, reopen it and join again before the movie starts. |
| Colors look wrong | Send Zach a screenshot. Do not change settings. |
| Wrong language or subtitles | Use the Audio and Subtitles buttons at the bottom of the player. Only your screen changes. |
| "Invalid username or password" many times in a row | After 5 wrong tries the account locks. Ask Zach to unlock it. |
| Forgot your password | Ask Zach for a new one. |

Still stuck? Send Zach a screenshot of the player and of the Tailscale app.
