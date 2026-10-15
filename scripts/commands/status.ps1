# ppg status: what is running, what is mounted, what Jellyfin is set to do
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/common.ps1')
. (Join-Path $PSScriptRoot '../lib/jellyfin.ps1')
. (Join-Path $PSScriptRoot '../lib/host.ps1')
$cfg = Get-PpgConfig

function Show-Row { param([string]$Name, [string]$Value) Write-Host ('  {0,-22} {1}' -f $Name, $Value) }

Write-Host ''
Write-Host 'PPG Movie Night host' -ForegroundColor Cyan
Show-Row 'zurg (debrid)' $(if (Test-ZurgRunning -Config $cfg) { 'running' } else { 'NOT running' })
Show-Row "mount $($cfg.MountDrive)" $(if (Test-PpgMountReady -Config $cfg) { 'ready' } else { 'NOT ready' })
Show-Row 'jellyfin' $(if (Test-JellyfinRunning) { 'running' } else { 'NOT running' })

Connect-Jellyfin -Url $cfg.JellyfinUrl
try {
    $info = Invoke-RestMethod -Uri ($cfg.JellyfinUrl + '/System/Info/Public') -TimeoutSec 5
    Show-Row 'jellyfin version' $info.Version
    Show-Row 'address' $cfg.JellyfinUrl
} catch {
    Show-Row 'jellyfin answers' 'NO'
    Write-Host ''
    exit 0
}

$state = Get-PpgState -Config $cfg
if ($state -and $state.ApiKey) {
    Connect-Jellyfin -Url $cfg.JellyfinUrl -Token $state.ApiKey
    try {
        $enc = Invoke-Jf -Path '/System/Configuration/encoding'
        Show-Row 'hardware accel' "$($enc.HardwareAccelerationType)  (tone mapping: $($enc.EnableTonemapping))"
        $srv = Invoke-Jf -Path '/System/Configuration'
        $cap = [int]($srv.RemoteClientBitrateLimit / 1000000)
        Show-Row 'remote bitrate cap' $(if ($cap -eq 0) { 'none' } else { "$cap Mbps" })
        $counts = Invoke-Jf -Path '/Items/Counts'
        Show-Row 'movies / shows' "$($counts.MovieCount) / $($counts.SeriesCount)"
        $sessions = @(Invoke-Jf -Path '/Sessions' | Where-Object { $_.NowPlayingItem })
        Show-Row 'playing now' "$($sessions.Count)"
        foreach ($s in $sessions) {
            $mode = 'Direct'
            if ($s.PSObject.Properties['PlayState'] -and $s.PlayState.PlayMethod) { $mode = $s.PlayState.PlayMethod }
            Show-Row "  $($s.UserName)" "$($s.NowPlayingItem.Name)  [$mode]"
        }
    } catch { Write-PpgWarn $_.Exception.Message }
} else {
    Write-PpgWarn 'Not set up yet. Run: ppg install'
}
Write-Host ''
