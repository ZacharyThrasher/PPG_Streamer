# ppg start: start the debrid mount, then Jellyfin (this is what runs at logon)
param([switch]$NoWait)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/common.ps1')
. (Join-Path $PSScriptRoot '../lib/jellyfin.ps1')
. (Join-Path $PSScriptRoot '../lib/host.ps1')
$cfg = Get-PpgConfig

Write-PpgInfo 'Starting the debrid mount'
Start-PpgZurg -Config $cfg
if (-not $NoWait) {
    if (Wait-PpgMount -Config $cfg -TimeoutSec 120) { Write-PpgOk "Debrid library ready at $($cfg.MountDrive)" }
    else { Write-PpgWarn "The debrid drive $($cfg.MountDrive) has not appeared yet. Jellyfin will still start; run: ppg doctor" }
}
Write-PpgInfo 'Starting Jellyfin'
Start-PpgJellyfin
if (-not $NoWait) {
    Connect-Jellyfin -Url $cfg.JellyfinUrl
    try { $info = Wait-Jellyfin -TimeoutSec 120; Write-PpgOk "Jellyfin $($info.Version) is up at $($cfg.JellyfinUrl)" }
    catch { Write-PpgWarn $_.Exception.Message }
}
