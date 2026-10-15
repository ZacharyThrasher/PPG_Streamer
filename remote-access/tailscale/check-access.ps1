<#
.SYNOPSIS
  Quick health check for friend access over Tailscale. Read-only.

.DESCRIPTION
  Run on the Jellyfin host. Prints PASS / WARN / FAIL for each thing that has to
  be true for a friend to get in, and what to do about it.

.PARAMETER JellyfinPort
  Local Jellyfin HTTP port. Default 8096.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\check-access.ps1
#>
[CmdletBinding()]
param(
    [int]$JellyfinPort = 8096
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$script:Failures = 0
function Pass([string]$Text) { Write-Host "[PASS] $Text" -ForegroundColor Green }
function Warn([string]$Text) { Write-Host "[WARN] $Text" -ForegroundColor Yellow }
function Fail([string]$Text) { Write-Host "[FAIL] $Text" -ForegroundColor Red; $script:Failures++ }

# 1. Tailscale CLI
$ts = (Get-Command tailscale -ErrorAction SilentlyContinue).Source
if (-not $ts) {
    $default = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    if (Test-Path $default) { $ts = $default }
}
if (-not $ts) {
    Fail 'Tailscale is not installed. Run setup-host.ps1.'
    exit 1
}
Pass "Tailscale found at $ts"

# 2. Signed in and running
$json = & $ts status --json 2>$null
$status = $null
if ($LASTEXITCODE -eq 0 -and $json) { $status = ($json -join "`n") | ConvertFrom-Json }
if (-not $status -or $status.BackendState -ne 'Running') {
    Fail 'Tailscale is not connected. Open the Tailscale app and sign in, or run setup-host.ps1.'
    exit 1
}
$dnsName = $status.Self.DNSName.TrimEnd('.')
Pass "Tailscale is connected as $dnsName"

# 3. Jellyfin answering locally
try {
    $info = Invoke-RestMethod -Uri "http://127.0.0.1:$JellyfinPort/System/Info/Public" -TimeoutSec 5
    Pass "Jellyfin $($info.Version) answers on port $JellyfinPort"
} catch {
    Fail "Jellyfin does not answer on 127.0.0.1:$JellyfinPort. Start the Jellyfin service/tray app."
}

# 4. serve rule present
$serveText = (& $ts serve status 2>&1) -join "`n"
if ($serveText -match [regex]::Escape("127.0.0.1:$JellyfinPort") -or $serveText -match "localhost:$JellyfinPort") {
    Pass 'tailscale serve is forwarding to Jellyfin'
} else {
    Fail 'No tailscale serve rule for Jellyfin. Run setup-host.ps1.'
}
if ($serveText -match '(?i)funnel on') {
    Warn 'Funnel is ON for something on this PC. That is public internet exposure. Turn it off with: tailscale funnel reset'
}

# 5. HTTPS reachable through our own tailnet name (tests the cert + proxy chain)
try {
    $r = Invoke-WebRequest -Uri "https://$dnsName/System/Info/Public" -UseBasicParsing -TimeoutSec 10
    if ($r.StatusCode -eq 200) { Pass "https://$dnsName answers" }
    else { Warn "https://$dnsName returned HTTP $($r.StatusCode)" }
} catch {
    Warn "Could not load https://$dnsName from this PC: $($_.Exception.Message). If friends also fail, check serve status and the HTTPS setting at login.tailscale.com/admin/dns."
}

# 6. Who is connected, and is the path direct or relayed?
# A relayed path (CurAddr empty, Relay set) works but is slow; fine for chat, bad for 4K.
Write-Host ''
Write-Host 'Peers with recent activity:'
$any = $false
if ($status.PSObject.Properties.Name -contains 'Peer' -and $status.Peer) {
    foreach ($p in $status.Peer.PSObject.Properties.Value) {
        if (-not $p.Online) { continue }
        $any = $true
        $path = if ($p.CurAddr) { "direct ($($p.CurAddr))" } elseif ($p.Relay) { "RELAYED via $($p.Relay) (slower)" } else { 'idle / not yet connected' }
        Write-Host ("   {0,-30} {1}" -f $p.HostName, $path)
    }
}
if (-not $any) { Write-Host '   (none online right now)' }

Write-Host ''
if ($script:Failures -gt 0) {
    Write-Host "$($script:Failures) problem(s) found." -ForegroundColor Red
    exit 1
}
Write-Host 'All checks passed. Friends should be able to connect.' -ForegroundColor Green
