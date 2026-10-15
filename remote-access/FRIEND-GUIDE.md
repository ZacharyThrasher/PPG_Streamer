# Movie night: getting connected (5 minutes, one time)

You only do this once. After that it is "open the bookmark and log in".

## You need

- A computer, phone or tablet
- A Google, Microsoft, Apple or GitHub account (any one; free)
- The invite link from Zach
- Your Jellyfin username and password from Zach

## Steps

1. **Install Tailscale.** Get it from https://tailscale.com/download (Windows, Mac, Linux, iPhone, Android). Open it and sign in with your Google/Microsoft/Apple/GitHub account.
   - Tailscale is a small private-network app. It does not slow down your normal internet.
2. **Click the invite link Zach sent you.** Sign in if asked, then press **Accept**.
   - You should see Zach's PC appear in your Tailscale device list.
3. **Open the movie address** Zach sent (it looks like `https://something.tailnet-name.ts.net`) in your browser. Bookmark it.
4. **Log in** with the username and password Zach gave you.

You are done. When movie night starts, Zach will tell you when to join.

## If something does not work

| What you see | Try this |
|---|---|
| "Can't reach this site" / page never loads | Open the Tailscale app and make sure it says Connected. Then reload. |
| Step 2 says the invite is used or expired | Ask Zach for a new link. Each one works once and expires after 30 days. |
| Page loads but video is choppy | Tell Zach. It may be using a slow route and he can check. Close other heavy downloads or streams. |
| Phone: Tailscale turns off by itself | Phones allow one VPN at a time. Turn off any other VPN app. |
| Smart TV or streaming box | Many cannot run Tailscale. Use a laptop/phone and cast or plug in by HDMI, or tell Zach what device you have. |

Still stuck? Send Zach a screenshot of the Tailscale app and the error page.

---

## For Zach: copy-paste invite message

```
Movie night setup, takes about 5 minutes, one time:

1. Install Tailscale: https://tailscale.com/download  (sign in with Google/Microsoft/Apple/GitHub)
2. Click this link and press Accept: <INVITE_LINK>
3. Open <JELLYFIN_URL> and bookmark it
4. Log in:  username <USER>   password <PASSWORD>

Stuck? Screenshot the Tailscale app and send it to me.
```

Send the password separately from the link if you like. Each invite link should go to one friend only.
