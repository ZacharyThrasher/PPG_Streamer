# ppg scan: ask Jellyfin to look for new movies and shows (reads folder listings, not whole files)
param([switch]$Quiet)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/common.ps1')
. (Join-Path $PSScriptRoot '../lib/jellyfin.ps1')
$cfg = Get-PpgConfig
$state = Get-PpgState -Config $cfg
if (-not $state -or -not $state.ApiKey) { throw 'Not set up yet. Run: ppg install' }
Connect-Jellyfin -Url $cfg.JellyfinUrl -Token $state.ApiKey
Invoke-Jf -Method POST -Path '/Library/Refresh' | Out-Null
if (-not $Quiet) { Write-PpgOk 'Scan requested. New titles appear in a minute or two.' }
