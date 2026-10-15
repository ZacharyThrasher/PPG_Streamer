# Runs the Jellyfin bootstrap against a throwaway Jellyfin server and checks the result.
# Usage: pwsh tests/test-bootstrap.ps1 -Url http://localhost:8096 -LibraryRoot /media
# The server must be freshly started (first-run wizard not completed) and the
# LibraryRoot must contain 'movies' and 'shows' folders.
param(
    [string]$Url = 'http://localhost:8096',
    [string]$LibraryRoot = '/media'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ppg-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

$cfgFile = Join-Path $tmp 'ppg.config.psd1'
@"
@{
    InstallRoot = '$tmp'
    JellyfinUrl = '$Url'
    LibraryRoot = '$LibraryRoot'
    RemoteBitrateLimitMbps = 40
}
"@ | Set-Content $cfgFile
$env:PPG_CONFIG = $cfgFile

. (Join-Path $repo 'scripts/lib/common.ps1')
. (Join-Path $repo 'scripts/lib/jellyfin.ps1')
$cfg = Get-PpgConfig

$failures = New-Object System.Collections.ArrayList
function Assert-Eq($name, $actual, $expected) {
    if ("$actual" -ne "$expected") { [void]$failures.Add("$name : expected '$expected' got '$actual'"); Write-Host "FAIL $name (expected '$expected', got '$actual')" -ForegroundColor Red }
    else { Write-Host "pass $name" -ForegroundColor Green }
}

# Run twice: the second run proves it is safe to repeat.
Invoke-PpgBootstrap -Config $cfg -SkipHooks
Invoke-PpgBootstrap -Config $cfg -SkipHooks

$enc = Invoke-Jf -Path '/System/Configuration/encoding'
Assert-Eq 'hwaccel is nvenc' $enc.HardwareAccelerationType 'nvenc'
Assert-Eq 'hardware encoding on' $enc.EnableHardwareEncoding $true
Assert-Eq 'tone mapping on' $enc.EnableTonemapping $true
Assert-Eq 'enhanced nvdec on' $enc.EnableEnhancedNvdecDecoder $true
Assert-Eq 'hevc 10-bit decode on' $enc.EnableDecodingColorDepth10Hevc $true
Assert-Eq 'hevc in decoder list' (@($enc.HardwareDecodingCodecs) -contains 'hevc') $true

$srv = Invoke-Jf -Path '/System/Configuration'
Assert-Eq 'quick connect on' $srv.QuickConnectAvailable $true
Assert-Eq 'scan concurrency' $srv.LibraryScanFanoutConcurrency 2
Assert-Eq 'remote cap bps' $srv.RemoteClientBitrateLimit 40000000
Assert-Eq 'server name' $srv.ServerName 'PPG Movie Night'

$libs = @(Invoke-Jf -Path '/Library/VirtualFolders')
Assert-Eq 'library count' $libs.Count 2
foreach ($l in $libs) {
    Assert-Eq "$($l.Name) realtime monitor off" $l.LibraryOptions.EnableRealtimeMonitor $false
    Assert-Eq "$($l.Name) trickplay off" $l.LibraryOptions.EnableTrickplayImageExtraction $false
    Assert-Eq "$($l.Name) chapter images off" $l.LibraryOptions.EnableChapterImageExtraction $false
    Assert-Eq "$($l.Name) save subtitles with media off" $l.LibraryOptions.SaveSubtitlesWithMedia $false
}
$movies = $libs | Where-Object { $_.Name -eq 'Movies' }
Assert-Eq 'movies path' ($movies.Locations -join ',') (Join-Path $LibraryRoot 'movies')

$tasks = @(Invoke-Jf -Path '/ScheduledTasks')
$bulk = @($tasks | Where-Object { ($_.Name -match 'Trickplay|Chapter|Segment|Scan Media Library') -and @($_.Triggers).Count -gt 0 })
Assert-Eq 'no bulk media jobs left on a schedule' $bulk.Count 0

$user = (Invoke-Jf -Path '/Users') | Where-Object { $_.Name -eq 'ppg-admin' }
Assert-Eq 'admin user exists' (@($user).Count) 1
Assert-Eq 'syncplay access for admin' $user.Policy.SyncPlayAccess 'CreateAndJoinGroups'

if ($failures.Count -gt 0) { Write-Host "$($failures.Count) check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All checks passed' -ForegroundColor Green
