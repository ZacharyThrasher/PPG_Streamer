<#
.SYNOPSIS
  One-time host setup so friends can reach Jellyfin over Tailscale.

.DESCRIPTION
  Run on the Windows PC that hosts Jellyfin. Safe to re-run.
    1. Installs Tailscale with winget if it is missing.
    2. Signs the PC in to your tailnet (opens a browser the first time).
    3. Checks Jellyfin answers on this PC.
    4. Publishes Jellyfin to your tailnet as https://<pc>.<tailnet>.ts.net using
       "tailscale serve". This is tailnet-only. It is NOT Tailscale Funnel, so
       nothing is exposed to the public internet.
    5. Prints the URL to give friends and the next manual steps.

  -Undo removes the serve rule again.

.PARAMETER JellyfinPort
  Local Jellyfin HTTP port. Default 8096.

.PARAMETER Undo
  Remove the tailscale serve rule and exit.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\setup-host.ps1
#>
[CmdletBinding()]
param(
    [int]$JellyfinPort = 8096,
    [switch]$Undo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step([string]$Text) { Write-Host ""; Write-Host "== $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host "   ok: $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "   warning: $Text" -ForegroundColor Yellow }

function Find-Tailscale {
    $cmd = Get-Command tailscale -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $default = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    if (Test-Path $default) { return $default }
    return $null
}

# Run tailscale and return its output. Throws on a non-zero exit code.
function Invoke-Tailscale([string[]]$TsArgs) {
    # Windows PowerShell 5.1 turns native stderr output into a terminating error
    # under 'Stop'. Relax it here and judge success by the exit code instead.
    $ErrorActionPreference = 'Continue'
    $output = & $script:Ts @TsArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "tailscale $($TsArgs -join ' ') failed (exit $LASTEXITCODE):`n$($output -join "`n")"
    }
    return $output
}

function Get-TailscaleStatus {
    $json = & $script:Ts status --json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return $null }
    return ($json -join "`n") | ConvertFrom-Json
}

# --- 1. Tailscale installed? -------------------------------------------------
Write-Step 'Checking for Tailscale'
$Ts = Find-Tailscale
if (-not $Ts) {
    if ($Undo) { Write-Host 'Tailscale is not installed; nothing to undo.'; return }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'Tailscale is not installed and winget is not available. Install Tailscale from https://tailscale.com/download/windows and re-run this script.'
    }
    Write-Host '   Installing Tailscale with winget...'
    winget install --id Tailscale.Tailscale --exact --silent --accept-package-agreements --accept-source-agreements
    $Ts = Find-Tailscale
    if (-not $Ts) { throw 'Tailscale installed but tailscale.exe was not found. Open a new terminal and re-run this script.' }
}
Write-Ok "using $Ts"

if ($Undo) {
    Write-Step 'Removing the tailscale serve rule'
    Invoke-Tailscale @('serve', 'reset') | Out-Null
    Write-Ok 'serve rule removed. Jellyfin is no longer published to your tailnet.'
    return
}

# --- 2. Signed in? -----------------------------------------------------------
Write-Step 'Checking Tailscale sign-in'
$status = Get-TailscaleStatus
if (-not $status -or $status.BackendState -ne 'Running') {
    Write-Host '   Not signed in yet. A browser window will open. Sign in, then come back here.'
    # --unattended keeps the PC on your tailnet even when nobody is logged in to Windows.
    & $Ts up --unattended
    if ($LASTEXITCODE -ne 0) { throw 'tailscale up failed. Sign in and re-run this script.' }
    $status = Get-TailscaleStatus
}
if (-not $status -or $status.BackendState -ne 'Running') {
    throw "Tailscale is not running (state: $(if ($status) { $status.BackendState } else { 'unknown' })). Open the Tailscale app, sign in, then re-run."
}
$dnsName = $status.Self.DNSName.TrimEnd('.')
Write-Ok "signed in as $dnsName"

# --- 3. Jellyfin up locally? -------------------------------------------------
Write-Step "Checking Jellyfin on this PC (port $JellyfinPort)"
try {
    $info = Invoke-RestMethod -Uri "http://127.0.0.1:$JellyfinPort/System/Info/Public" -TimeoutSec 5
    Write-Ok "Jellyfin $($info.Version) is answering (server name: $($info.ServerName))"
} catch {
    Write-Warn "Jellyfin did not answer on 127.0.0.1:$JellyfinPort. Start Jellyfin, or pass -JellyfinPort. Continuing; the serve rule can be set up before Jellyfin is running."
}

# --- 4. Publish to the tailnet -----------------------------------------------
Write-Step 'Publishing Jellyfin to your tailnet over HTTPS'
try {
    # Port 443 + tailnet only. "serve" never touches the public internet; "funnel" would.
    Invoke-Tailscale @('serve', '--bg', '--https=443', "http://127.0.0.1:$JellyfinPort") | Out-Null
    Write-Ok 'serve rule set'
} catch {
    Write-Host ''
    Write-Warn 'tailscale serve failed. The usual cause is that HTTPS certificates are not enabled for your tailnet yet.'
    Write-Host '   Fix: open https://login.tailscale.com/admin/dns , turn on MagicDNS, then click "Enable HTTPS". Then re-run this script.'
    Write-Host ''
    Write-Host "   Details: $($_.Exception.Message)"
    exit 1
}

# --- 5. Summary --------------------------------------------------------------
$url = "https://$dnsName"
Write-Step 'Done. What to do next'
Write-Host "   Friends will open:  $url" -ForegroundColor Green
Write-Host ''
Write-Host '   Manual steps (cannot be scripted):'
Write-Host '   1. Admin console > Machines: open the menu on this PC > "Disable key expiry".'
Write-Host '      (Otherwise this PC drops off your tailnet every 180 days.)'
Write-Host '   2. Admin console > Machines: menu on this PC > Share > create an invite link.'
Write-Host '      Send one link per friend (single use), plus remote-access/FRIEND-GUIDE.md.'
Write-Host '   3. Create a Jellyfin user for each friend (Dashboard > Users). Do not share your admin login.'
Write-Host ''
Write-Host "   Note: friends reach this PC by its full name ($dnsName), not the short name."
Write-Host '   To check on things later:  .\check-access.ps1'
Write-Host '   To turn it off:            .\setup-host.ps1 -Undo'
