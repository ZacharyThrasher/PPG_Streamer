# Shared helpers: config, state, logging. Dot-source this file.
# Written for Windows PowerShell 5.1 (the one built into Windows) and pwsh 7.

Set-StrictMode -Version 1.0

$script:PpgRoot = (Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') '..')).Path

function Test-PpgWindows {
    return ($env:OS -eq 'Windows_NT')
}

function Get-PpgRoot {
    return $script:PpgRoot
}

# ---- output ---------------------------------------------------------------

function Write-PpgStep { param([string]$Text) Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan }
function Write-PpgOk   { param([string]$Text) Write-Host "[ok]   $Text" -ForegroundColor Green }
function Write-PpgInfo { param([string]$Text) Write-Host "[info] $Text" }
function Write-PpgWarn { param([string]$Text) Write-Host "[warn] $Text" -ForegroundColor Yellow }
function Write-PpgFail { param([string]$Text) Write-Host "[FAIL] $Text" -ForegroundColor Red }

# ---- config ---------------------------------------------------------------

function Get-PpgDefaults {
    return @{
        MountDrive             = 'Z:'
        InstallRoot            = 'C:\PPG'
        JellyfinUrl            = 'http://localhost:8096'
        ServerName             = 'PPG Movie Night'
        AdminUser              = 'ppg-admin'
        RemoteBitrateLimitMbps = 0
        ScanConcurrency        = 2
        TranscodePath          = ''
        JellyfinMinVersion     = '12.2.0'
        Libraries              = @(
            @{ Name = 'Movies'; Type = 'movies';  Folder = 'movies' }
            @{ Name = 'Shows';  Type = 'tvshows'; Folder = 'shows' }
        )
        Remote                 = @{}
        Friends                = @{}
    }
}

# Defaults, overlaid with config/ppg.config.psd1 (or the file named by $env:PPG_CONFIG).
function Get-PpgConfig {
    $cfg = Get-PpgDefaults
    $path = $env:PPG_CONFIG
    if (-not $path) { $path = Join-Path $script:PpgRoot 'config/ppg.config.psd1' }
    if (Test-Path -LiteralPath $path) {
        $user = Import-PowerShellDataFile -LiteralPath $path
        foreach ($key in $user.Keys) { $cfg[$key] = $user[$key] }
    }
    $cfg.Root       = $script:PpgRoot
    $cfg.ZurgDir    = Join-Path $cfg.InstallRoot 'zurg'
    $cfg.StateDir   = Join-Path $cfg.InstallRoot 'state'
    $cfg.LogDir     = Join-Path $cfg.InstallRoot 'logs'
    $cfg.StatePath  = Join-Path $cfg.StateDir 'state.json'
    # LibraryRoot defaults to the debrid drive. Tests point it at a plain folder.
    if (-not $cfg.ContainsKey('LibraryRoot') -or -not $cfg.LibraryRoot) {
        $cfg.LibraryRoot = $cfg.MountDrive.TrimEnd('\', '/') + '\'
    }
    return $cfg
}

# ---- state (admin login, API key) ----------------------------------------

function Get-PpgState {
    param($Config)
    if (Test-Path -LiteralPath $Config.StatePath) {
        return Get-Content -LiteralPath $Config.StatePath -Raw | ConvertFrom-Json
    }
    return $null
}

function Save-PpgState {
    param($Config, [hashtable]$Values)
    New-Item -ItemType Directory -Force -Path $Config.StateDir | Out-Null
    $existing = @{}
    $current = Get-PpgState -Config $Config
    if ($current) {
        foreach ($p in $current.PSObject.Properties) { $existing[$p.Name] = $p.Value }
    }
    foreach ($key in $Values.Keys) { $existing[$key] = $Values[$key] }
    $existing | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Config.StatePath -Encoding UTF8
    Protect-PpgFile -Path $Config.StatePath
}

# Remove access for everyone except the current user (Windows only).
function Protect-PpgFile {
    param([string]$Path)
    if (-not (Test-PpgWindows)) { return }
    try {
        $me = "$env:USERDOMAIN\$env:USERNAME"
        & icacls.exe $Path /inheritance:r /grant:r "${me}:(F)" 2>&1 | Out-Null
    } catch {
        Write-PpgWarn "Could not restrict permissions on $Path"
    }
}

function New-PpgPassword {
    param([int]$Length = 20)
    $chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray()
    $bytes = New-Object byte[] $Length
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $rng.Dispose()
    $out = New-Object System.Text.StringBuilder
    foreach ($b in $bytes) { [void]$out.Append($chars[$b % $chars.Length]) }
    return $out.ToString()
}

# ---- misc -----------------------------------------------------------------

function Get-PpgLibraryPath {
    param($Config, $Library)
    return (Join-Path $Config.LibraryRoot $Library.Folder)
}

# Windows only: where the Jellyfin installer put things.
function Get-JellyfinInstall {
    if (-not (Test-PpgWindows)) { return $null }
    $key = 'HKLM:\SOFTWARE\WOW6432Node\Jellyfin\Server'
    $install = $null; $data = $null; $svc = 'None'
    if (Test-Path $key) {
        $props = Get-ItemProperty $key
        if ($props.PSObject.Properties['InstallFolder']) { $install = $props.InstallFolder }
        if ($props.PSObject.Properties['DataFolder']) { $data = $props.DataFolder }
        if ($props.PSObject.Properties['ServiceAccountType']) { $svc = $props.ServiceAccountType }
    }
    if (-not $install) { $install = Join-Path $env:ProgramFiles 'Jellyfin\Server' }
    return [pscustomobject]@{
        InstallFolder = $install
        DataFolder    = $data
        ServiceType   = $svc
        ServerExe     = Join-Path $install 'jellyfin.exe'
        TrayExe       = Join-Path $install 'Jellyfin.Windows.Tray.exe'
        FfmpegExe     = Join-Path $install 'ffmpeg.exe'
        FfprobeExe    = Join-Path $install 'ffprobe.exe'
    }
}

function Compare-PpgVersion {
    # Returns -1, 0, 1 comparing "12.2.0" style versions.
    param([string]$A, [string]$B)
    $va = [version]($A -replace '[^\d\.].*$', '')
    $vb = [version]($B -replace '[^\d\.].*$', '')
    return $va.CompareTo($vb)
}
