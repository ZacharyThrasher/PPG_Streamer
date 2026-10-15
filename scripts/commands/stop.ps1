# ppg stop: stop Jellyfin and the debrid mount (do this before shutting down for a long time or updating)
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/common.ps1')
. (Join-Path $PSScriptRoot '../lib/host.ps1')
$cfg = Get-PpgConfig
Stop-PpgJellyfin
Write-PpgOk 'Jellyfin stopped'
Stop-PpgZurg -Config $cfg
Write-PpgOk 'Debrid mount stopped'
