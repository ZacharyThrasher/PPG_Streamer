# ppg bootstrap: apply NVENC, tone mapping, libraries and no-scan settings to a running Jellyfin (safe to repeat)
param([string]$AdminPassword, [switch]$SkipHooks)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/common.ps1')
. (Join-Path $PSScriptRoot '../lib/jellyfin.ps1')
$cfg = Get-PpgConfig
Invoke-PpgBootstrap -Config $cfg -AdminPassword $AdminPassword -SkipHooks:$SkipHooks
Write-Host ''
Write-PpgOk 'Jellyfin is configured.'
