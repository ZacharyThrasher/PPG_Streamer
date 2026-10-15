# SyncPlay cheat sheet

SyncPlay is Jellyfin's built-in "watch together". The server keeps everyone's play, pause and position in step. Nobody needs to install or configure anything extra.

## For friends (5 lines, paste-able)

```
Joining movie night:
1. Open Jellyfin Media Player (Tailscale connected).
2. Wait for Zach to say the group is ready.
3. Click the people icon in the top bar, press Zach's group. You see "SyncPlay enabled".
4. Do nothing. When Zach presses play, it starts for you.
Anyone's pause pauses everyone. Please do not drag the seek bar. Problem: tell Zach, he restarts the movie for everyone.
```

## For the host (Zach)

### Start a night

1. Everyone is in the voice call and has joined Tailscale.
2. Open Jellyfin (the player or the browser). Open the movie's page, not the player yet.
3. Click the people icon in the top bar, then "New group". You see "SyncPlay enabled".
4. Tell everyone: "group is ready". Watch the people icon menu: it lists who has joined.
5. When everyone is in, press play on the movie page. Friends' players open and start by themselves.

### While it plays

| Want to | Do this |
|---|---|
| Pause for everyone | Pause normally. Anyone's pause pauses everyone (checked with two users). |
| Skip or seek | Seek normally. Everyone jumps to the same spot (checked). |
| Someone buffers | The group waits for them. Nothing to do. |
| See who is in the group | People icon: the group name and members are listed. |
| A friend joins late | They join the group; their player opens at the group's position (checked). |
| One friend is stuck or out of step | Close the player (back arrow) and press Resume or Play again. Everyone restarts together (checked). |
| Stop one player without ending the group | People icon, "Stop local playback" (menu item seen, not tried). |

### Why friends can only join, not create

New accounts get SyncPlay access `JoinGroups`. That means one group per night, yours. A friend who clicks the icon before you create the group sees "Permission required to create a group". That message is the signal to wait. Give someone create rights with `New-FriendAccount.ps1 -AllowCreateGroups`.

### Keeping sync good

- SyncPlay is most reliable when every viewer Direct Plays (the file is played as is, nobody is transcoding). Server transcode load is a commonly reported cause of drift (secondary sources).
- A transcode happens when a friend uses the browser fallback, when the film is Dolby Vision (Jellyfin Media Player forces a server transcode for Dolby Vision by default, per its 1.9.0 release notes), or when you set a bitrate cap that is lower than the file.
- Pick a release that Direct Plays: H.264 or HEVC, HDR10 is fine, avoid Dolby Vision profile 5. See [README.md](README.md#picking-a-movie-that-direct-plays).
- Do not use Leave group then rejoin as a fix mid-movie. In testing it paused the group and the friend's player did not catch up (checked with the Jellyfin 12.2 web client). The reliable reset is the host closing the player and pressing Resume again.
- Known upstream rough edges: open Jellyfin issues describe auto-pauses, skips and desync when seeking, especially with the desktop app as host. If it happens, do the reset above. Do not seek twice in quick succession.
- No built-in chat or voice. Keep Discord for voice.

### Not working?

| Symptom | Likely cause | Fix |
|---|---|---|
| Friend says "Permission required to create a group" | Group not created yet | Create it, tell them to try again |
| Friend joined but nothing plays, group paused | They left and rejoined mid-movie | Close the player and press Resume again |
| Friend sees no group to join | You have not created it yet, or they are on a different server | Create the group; check the address they typed |
| Constant auto-pause | A friend is on a weak or relayed link | Run `remote-access\tailscale\check-access.ps1`, ask that friend to close downloads |
| Friend is a few seconds off | Transcoding or slow link | Do the reset above (close the player, Resume); check on the Jellyfin Dashboard home page that they show as Direct Play |
