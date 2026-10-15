# ppg install: one-time setup (WinFsp, Jellyfin, zurg debrid mount, NVENC settings, start at logon)
param(
    [string]$RdToken,          # Real-Debrid API token (or set RD_TOKEN, or you will be asked)
    [string]$ZurgVersion,      # release tag, default = latest
    [string]$AdminPassword,    # default = generated
    [switch]$SkipJellyfinInstall,
    [switch]$SkipStartupEntry
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/common.ps1')
. (Join-Path $PSScriptRoot '../lib/jellyfin.ps1')
. (Join-Path $PSScriptRoot '../lib/host.ps1')

if (-not (Test-PpgWindows)) { throw 'ppg install is for the Windows host PC.' }
$cfg = Get-PpgConfig
New-Item -ItemType Directory -Force -Path $cfg.InstallRoot, $cfg.ZurgDir, $cfg.StateDir, $cfg.LogDir | Out-Null

# ---- 1. prerequisites -----------------------------------------------------
Write-PpgStep '1/6  Checking this PC'
if (-not (Test-WinGetAvailable)) {
    throw 'winget was not found. Install "App Installer" from the Microsoft Store, then run this again.'
}
$driveLetter = $cfg.MountDrive.TrimEnd(':')
if ((Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue) -and -not (Test-ZurgRunning -Config $cfg)) {
    throw "Drive $($cfg.MountDrive) is already in use. Pick a free letter in config\ppg.config.psd1 (MountDrive)."
}
$smi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
if ($smi) {
    Write-PpgOk ('GPU: ' + ((& nvidia-smi.exe --query-gpu=name,driver_version --format=csv,noheader) -join '; '))
} else {
    Write-PpgWarn 'nvidia-smi not found. NVENC needs the NVIDIA driver. Movies still play, but HDR to SDR conversion will not work until it is installed.'
}

if (-not (Test-WinFspInstalled)) {
    Write-PpgInfo 'Installing WinFsp (lets Windows mount the debrid library as a drive)'
    if (-not (Install-WithWinGet -Id 'WinFsp.WinFsp')) {
        throw 'WinFsp install failed. Install it from https://winfsp.dev/rel/ and run this again.'
    }
    Write-PpgWarn 'WinFsp was just installed. If the mount does not appear later, reboot once and run: ppg start'
} else { Write-PpgOk 'WinFsp is installed' }

# ---- 2. Jellyfin ----------------------------------------------------------
Write-PpgStep '2/6  Jellyfin'
$jf = Get-JellyfinInstall
if (-not (Test-Path -LiteralPath $jf.ServerExe) -and -not $SkipJellyfinInstall) {
    Write-PpgInfo 'Installing Jellyfin Server (leave the "install as service" option OFF if the installer asks)'
    if (-not (Install-WithWinGet -Id 'Jellyfin.Server')) {
        throw 'Jellyfin install failed. Install Jellyfin Server from https://jellyfin.org/downloads/server and run this again.'
    }
    $jf = Get-JellyfinInstall
}
if (-not (Test-Path -LiteralPath $jf.ServerExe)) { throw "Jellyfin not found at $($jf.ServerExe)." }
if ($jf.ServiceType -ne 'None') {
    throw "Jellyfin is installed as a Windows service ($($jf.ServiceType)); a service cannot see the debrid drive. Uninstall Jellyfin, then run this again (it reinstalls without the service)."
}
Write-PpgOk "Jellyfin found: $($jf.InstallFolder)"

# ---- 3. zurg --------------------------------------------------------------
Write-PpgStep '3/6  Debrid mount (zurg + rclone)'
$token = $RdToken
if (-not $token) { $token = $env:RD_TOKEN }
if (-not $token) { $token = Get-ZurgToken -Config $cfg }
if (-not $token -or $token -eq 'yourtoken') {
    Write-Host 'Paste your Real-Debrid API token (from https://real-debrid.com/apitoken). Input is hidden.'
    $secure = Read-Host -AsSecureString 'Real-Debrid token'
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
$token = $token.Trim()
try {
    $rd = Get-RdUser -Token $token
    Write-PpgOk "Real-Debrid account: $($rd.username), premium: $($rd.premium -gt 0), expires: $($rd.expiration)"
    if ($rd.type -ne 'premium') { Write-PpgWarn 'This account is not premium; the library will be empty.' }
} catch {
    throw "Real-Debrid rejected that token ($($_.Exception.Message)). Copy it again from https://real-debrid.com/apitoken"
}

$zurgExe = Join-Path $cfg.ZurgDir 'zurg.exe'
if (-not (Test-Path -LiteralPath $zurgExe)) {
    $url = Get-ZurgReleaseUrl -Version $ZurgVersion
    Write-PpgInfo "Downloading $url"
    $zip = Join-Path $env:TEMP 'zurg-windows.zip'
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Expand-Archive -LiteralPath $zip -DestinationPath $cfg.ZurgDir -Force
    Remove-Item -LiteralPath $zip -Force
    if (-not (Test-Path -LiteralPath $zurgExe)) {
        $found = Get-ChildItem -Path $cfg.ZurgDir -Filter 'zurg.exe' -Recurse | Select-Object -First 1
        if (-not $found) { throw 'zurg.exe not found after download.' }
        Move-Item -LiteralPath $found.FullName -Destination $zurgExe -Force
    }
}
Write-PpgOk "zurg: $zurgExe"

$hookFile = Join-Path $cfg.Root 'scripts/zurg-library-hook.ps1'
$hookCmd = "& powershell -ExecutionPolicy Bypass -File ""$hookFile"" --% ""`$args"""
$hookCmd = $hookCmd.Replace("'", "''")   # the value sits inside single quotes in YAML
$yaml = Get-Content -LiteralPath (Join-Path $cfg.Root 'config/zurg.config.yml.template') -Raw
$yaml = $yaml.Replace('{{TOKEN}}', $token).Replace('{{MOUNT}}', $cfg.MountDrive).Replace('{{LIBRARY_HOOK}}', $hookCmd)
$yamlPath = Join-Path $cfg.ZurgDir 'config.yml'
[IO.File]::WriteAllText($yamlPath, $yaml, (New-Object Text.UTF8Encoding $false))   # UTF-8, no BOM
Protect-PpgFile -Path $yamlPath
Write-PpgOk 'zurg config written (token stays in this folder, never in the repo)'

# ---- 4. start everything --------------------------------------------------
Write-PpgStep '4/6  Starting the debrid mount'
if (Test-ZurgRunning -Config $cfg) { Stop-PpgZurg -Config $cfg; Start-Sleep -Seconds 2 }
Start-PpgZurg -Config $cfg
if (-not (Wait-PpgMount -Config $cfg -TimeoutSec 180)) {
    $needed = Join-Path $cfg.ZurgDir 'bin\rclone.exe'
    if (-not (Test-Path -LiteralPath $needed)) {
        Write-PpgInfo 'zurg has not fetched rclone yet; asking it to download requirements'
        Stop-PpgZurg -Config $cfg
        Push-Location $cfg.ZurgDir
        try { & $zurgExe download-requirements -c $yamlPath } finally { Pop-Location }
        Start-PpgZurg -Config $cfg
        [void](Wait-PpgMount -Config $cfg -TimeoutSec 120)
    }
}
if (-not (Test-PpgMountReady -Config $cfg)) {
    throw "The debrid drive $($cfg.MountDrive) did not appear. Check $($cfg.ZurgDir)\logs, and see docs\TROUBLESHOOTING.md (WinFsp reboot, drive letter, token)."
}
Write-PpgOk "Debrid library is mounted at $($cfg.MountDrive)"

Write-PpgStep '5/6  Starting Jellyfin and applying settings'
Start-PpgJellyfin
Invoke-PpgBootstrap -Config $cfg -AdminPassword $AdminPassword

# ---- 6. start at logon ----------------------------------------------------
Write-PpgStep '6/6  Start at logon'
if (-not $SkipStartupEntry) {
    Install-PpgStartup -Config $cfg
    Write-PpgOk 'Added "PPG Movie Night" to your Startup folder. It starts the mount and Jellyfin when you sign in.'
}

$state = Get-PpgState -Config $cfg
Write-Host ''
Write-Host 'All set.' -ForegroundColor Green
Write-Host "  Open Jellyfin:  $($cfg.JellyfinUrl)"
Write-Host "  Admin login:    $($state.AdminUser) / (password saved in $($cfg.StatePath))"
Write-Host '  Next:           ppg doctor      (checks NVENC, tone mapping, mount)'
Write-Host '                  add a movie to your Real-Debrid library, then: ppg scan'
