# Called by zurg whenever the debrid library changes. Turns a burst of changes
# into one Jellyfin scan: the first call waits, later calls in that window do nothing.
param([switch]$Delayed)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/common.ps1')
$cfg = Get-PpgConfig
$marker = Join-Path $cfg.StateDir 'scan-pending'
New-Item -ItemType Directory -Force -Path $cfg.StateDir, $cfg.LogDir | Out-Null

if (-not $Delayed) {
    if (Test-Path -LiteralPath $marker) {
        $age = (Get-Date) - (Get-Item -LiteralPath $marker).LastWriteTime
        if ($age.TotalMinutes -lt 5) { exit 0 }
    }
    Set-Content -LiteralPath $marker -Value (Get-Date).ToString('o')
    $self = $MyInvocation.MyCommand.Path
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$self`"", '-Delayed')
    exit 0
}

Start-Sleep -Seconds 45
Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
try { & (Join-Path $cfg.Root 'scripts/commands/scan.ps1') -Quiet }
catch { Add-Content -Path (Join-Path $cfg.LogDir 'hook.log') -Value "$(Get-Date -Format o) scan failed: $($_.Exception.Message)" }
