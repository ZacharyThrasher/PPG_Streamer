# ppg uninstall: stop everything and remove the start-at-logon entry (keeps Jellyfin, your library and saved settings)
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/common.ps1')
. (Join-Path $PSScriptRoot '../lib/jellyfin.ps1')
. (Join-Path $PSScriptRoot '../lib/host.ps1')
$cfg = Get-PpgConfig
Stop-PpgJellyfin
Stop-PpgZurg -Config $cfg
Uninstall-PpgStartup
Write-PpgOk 'Stopped, and removed from Startup.'
Write-PpgInfo "Left in place: Jellyfin itself, $($cfg.InstallRoot) (zurg, state, logs). Delete that folder to remove them. Remove Jellyfin and WinFsp from Settings > Apps."
