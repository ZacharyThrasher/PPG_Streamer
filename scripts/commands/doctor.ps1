# ppg doctor: check GPU, NVENC, tone mapping, debrid mount and Jellyfin settings; says what to fix
param([switch]$SkipEncodeTest)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/common.ps1')
. (Join-Path $PSScriptRoot '../lib/jellyfin.ps1')
. (Join-Path $PSScriptRoot '../lib/host.ps1')
$cfg = Get-PpgConfig

$script:fails = 0
$script:warns = 0
function Pass { param([string]$Text) Write-PpgOk $Text }
function Warn { param([string]$Text, [string]$Fix) $script:warns++; Write-PpgWarn $Text; if ($Fix) { Write-Host "         fix: $Fix" } }
function Fail { param([string]$Text, [string]$Fix) $script:fails++; Write-PpgFail $Text; if ($Fix) { Write-Host "         fix: $Fix" } }

if (-not (Test-PpgWindows)) { throw 'ppg doctor checks the Windows host PC.' }

# ---- GPU ------------------------------------------------------------------
Write-PpgStep 'GPU and driver'
$gpuName = ''
$smi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
if (-not $smi) {
    Fail 'nvidia-smi not found: no NVIDIA driver.' 'Install the latest Game Ready or Studio driver from nvidia.com.'
} else {
    $line = (& nvidia-smi.exe --query-gpu=name,driver_version --format=csv,noheader | Select-Object -First 1)
    $parts = $line -split ','
    $gpuName = $parts[0].Trim()
    $driver = $parts[1].Trim()
    Pass "GPU $gpuName, driver $driver"
    $minDriver = '522.25'
    if ($gpuName -match 'RTX 50') { $minDriver = '570.0' }
    if ((Compare-PpgVersion $driver $minDriver) -lt 0) {
        Fail "Driver $driver is older than $minDriver, which this GPU and Jellyfin need." 'Update the NVIDIA driver.'
    }
}

# ---- Jellyfin install -----------------------------------------------------
Write-PpgStep 'Jellyfin'
$jf = Get-JellyfinInstall
if (-not (Test-Path -LiteralPath $jf.ServerExe)) {
    Fail 'Jellyfin is not installed.' 'ppg install'
} else {
    Pass "Installed at $($jf.InstallFolder)"
    if ($jf.ServiceType -ne 'None') {
        Fail "Jellyfin runs as a Windows service ($($jf.ServiceType)); it cannot see the debrid drive." 'Uninstall Jellyfin and run: ppg install'
    }
}

# ---- NVENC and CUDA tone-map filter in Jellyfin's own ffmpeg ---------------
if ((Test-Path -LiteralPath $jf.FfmpegExe) -and $smi) {
    $filters = (& $jf.FfmpegExe -hide_banner -filters 2>&1 | Out-String)
    if ($filters -match 'tonemap_cuda') { Pass 'ffmpeg has the CUDA tone-mapping filter' }
    else { Fail 'ffmpeg has no tonemap_cuda filter.' 'Update Jellyfin (it ships jellyfin-ffmpeg).' }

    if (-not $SkipEncodeTest) {
        foreach ($enc in @('h264_nvenc', 'hevc_nvenc')) {
            $out = & $jf.FfmpegExe -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=1920x1080:rate=24' -t 2 -c:v $enc -f null - 2>&1
            if ($LASTEXITCODE -eq 0) { Pass "$enc test encode works" }
            else { Fail "$enc test encode failed: $(($out | Out-String).Trim())" 'Update the NVIDIA driver; close other apps using all NVENC sessions.' }
        }
    }
}

# ---- debrid mount ---------------------------------------------------------
Write-PpgStep 'Debrid mount'
if (-not (Test-WinFspInstalled)) { Fail 'WinFsp is not installed.' 'ppg install' }
if (Test-ZurgRunning -Config $cfg) { Pass 'zurg is running' } else { Fail 'zurg is not running.' 'ppg start' }
if (Test-PpgMountReady -Config $cfg) { Pass "Library mounted at $($cfg.MountDrive)" }
else { Fail "Nothing at $($cfg.MountDrive)\movies." 'ppg start; if still missing see docs\TROUBLESHOOTING.md' }

try {
    $conns = @(Get-NetTCPConnection -LocalPort 9999 -State Listen -ErrorAction Stop)
    $open = @($conns | Where-Object { $_.LocalAddress -notin @('127.0.0.1', '::1') })
    if ($open.Count -gt 0) { Fail 'zurg is listening on the network, not just this PC.' 'Set host: "127.0.0.1" in the zurg config.yml.' }
    elseif ($conns.Count -gt 0) { Pass 'zurg listens on this PC only' }
} catch { }

$token = Get-ZurgToken -Config $cfg
if ($token) {
    try {
        $rd = Get-RdUser -Token $token
        if ($rd.type -eq 'premium') { Pass "Real-Debrid premium OK until $($rd.expiration)" }
        else { Fail 'Real-Debrid account is not premium.' 'Renew at real-debrid.com.' }
    } catch { Fail "Real-Debrid token check failed: $($_.Exception.Message)" 'Run: ppg install -RdToken <new token>' }
}

# ---- Jellyfin settings ----------------------------------------------------
Write-PpgStep 'Jellyfin settings'
Connect-Jellyfin -Url $cfg.JellyfinUrl
$state = Get-PpgState -Config $cfg
$reach = $null
try { $reach = Invoke-RestMethod -Uri ($cfg.JellyfinUrl + '/System/Info/Public') -TimeoutSec 5 } catch { }
if (-not $reach) {
    Fail "Jellyfin does not answer at $($cfg.JellyfinUrl)." 'ppg start'
} else {
    if ((Compare-PpgVersion $reach.Version $cfg.JellyfinMinVersion) -ge 0) { Pass "Version $($reach.Version) (SyncPlay-safe, minimum $($cfg.JellyfinMinVersion))" }
    else { Fail "Version $($reach.Version) is older than $($cfg.JellyfinMinVersion); SyncPlay drifts on older versions." 'Install the latest Jellyfin Server over the top (ppg stop first).' }

    if (-not $state -or -not $state.ApiKey) {
        Fail 'No saved API key.' 'ppg install'
    } else {
        Connect-Jellyfin -Url $cfg.JellyfinUrl -Token $state.ApiKey
        $enc = Invoke-Jf -Path '/System/Configuration/encoding'
        if ($enc.HardwareAccelerationType -eq 'nvenc') { Pass 'Hardware acceleration: NVENC' } else { Fail "Hardware acceleration is '$($enc.HardwareAccelerationType)'." 'ppg bootstrap' }
        if ($enc.EnableTonemapping) { Pass 'HDR to SDR tone mapping on (CUDA)' } else { Fail 'Tone mapping is off.' 'ppg bootstrap' }
        if ($enc.EnableEnhancedNvdecDecoder) { Pass 'Enhanced NVDEC on (needed for Dolby Vision)' } else { Warn 'Enhanced NVDEC is off.' 'ppg bootstrap' }

        $libs = @(Invoke-Jf -Path '/Library/VirtualFolders')
        if ($libs.Count -eq 0) { Fail 'No libraries.' 'ppg bootstrap' }
        foreach ($l in $libs) {
            $o = $l.LibraryOptions
            $heavy = @()
            if ($o.EnableRealtimeMonitor) { $heavy += 'realtime monitor' }
            if ($o.EnableTrickplayImageExtraction) { $heavy += 'trickplay thumbnails' }
            if ($o.EnableChapterImageExtraction) { $heavy += 'chapter images' }
            if ($heavy.Count -gt 0) { Fail "Library '$($l.Name)' has $($heavy -join ', ') on: reads whole files off debrid." 'ppg bootstrap' }
            else { Pass "Library '$($l.Name)': no thumbnail or whole-file jobs" }
        }

        $srv = Invoke-Jf -Path '/System/Configuration'
        $cap = [int]($srv.RemoteClientBitrateLimit / 1000000)
        if ($cap -eq 0) { Warn 'No remote bitrate cap: a friend on a slow link can ask for more than your upload.' "After you measure upload, set RemoteBitrateLimitMbps in config\ppg.config.psd1 and run: ppg bootstrap" }
        else { Pass "Remote bitrate cap: $cap Mbps" }
    }
}

# ---- machine --------------------------------------------------------------
Write-PpgStep 'This PC'
try {
    $q = (& powercfg.exe /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE | Out-String)
    if ($q -match 'Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)') {
        $secs = [Convert]::ToInt32($Matches[1], 16)
        if ($secs -eq 0) { Pass 'PC does not sleep while plugged in' }
        else { Warn "PC sleeps after $([int]($secs / 60)) minutes idle; friends lose the movie if it does." 'Settings > System > Power: set Sleep (plugged in) to Never.' }
    }
} catch { }

Write-Host ''
if ($script:fails -gt 0) { Write-PpgFail "$($script:fails) problem(s), $($script:warns) warning(s)."; exit 1 }
Write-PpgOk "All good. $($script:warns) warning(s)."
