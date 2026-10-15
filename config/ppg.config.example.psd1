# PPG Movie Streamer host settings.
#
# Optional. Everything here has a working default, so you only need this file
# if you want to change something. To use it:
#   Copy-Item config\ppg.config.example.psd1 config\ppg.config.psd1
# ppg.config.psd1 is gitignored. Never put the Real-Debrid token in here; the
# installer asks for it once and stores it outside the repo.
@{
    # Drive letter where the debrid library appears. Must be free.
    MountDrive             = 'Z:'

    # Where zurg, logs and saved state live (outside the repo, so git never sees secrets).
    InstallRoot            = 'C:\PPG'

    # Jellyfin address as seen from this PC.
    JellyfinUrl            = 'http://localhost:8096'

    # Name friends see on their Jellyfin login screen.
    ServerName             = 'PPG Movie Night'

    # First admin account, created once by the installer. The password is
    # generated and saved to InstallRoot\state\state.json (readable by you only).
    AdminUser              = 'ppg-admin'

    # Cap for any friend streaming from outside your home network, in Mbps.
    # 0 = no cap (best quality, relies on your upload speed).
    # Rule of thumb: (home upload speed * 0.8) / number of friends watching.
    # Example: 300 Mbps up, 5 friends -> 48. Friends above the cap get a
    # transcode (GPU) instead of Direct Play, so do not set it lower than needed.
    RemoteBitrateLimitMbps = 0

    # How many files Jellyfin may probe at once during a library scan. Low on
    # purpose: every probe is a request to the debrid mount.
    ScanConcurrency        = 2

    # Fast SSD folder for transcode scratch files. Empty = Jellyfin default.
    TranscodePath          = ''

    # Libraries Jellyfin creates. Folder is the zurg folder under the mount.
    Libraries              = @(
        @{ Name = 'Movies'; Type = 'movies';  Folder = 'movies' }
        @{ Name = 'Shows';  Type = 'tvshows'; Folder = 'shows' }
    )

    # Oldest Jellyfin that is safe for SyncPlay (older versions drift when
    # anyone transcodes). The doctor fails below this.
    JellyfinMinVersion     = '12.2.0'

    # Reserved for the remote access and friend onboarding features. This
    # feature ignores these keys; they live here so one file configures everything.
    Remote                 = @{}
    Friends                = @{}
}
