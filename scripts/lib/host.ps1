# Windows host helpers: processes, mount, startup entry, zurg. Dot-source after common.ps1.

function Get-PpgProcessesUnder {
    # Processes (by name) whose exe lives under a folder.
    param([string[]]$Name, [string]$Folder)
    $out = @()
    foreach ($n in $Name) {
        foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) {
            $path = $null
            try { $path = $p.Path } catch { }
            if (-not $Folder -or ($path -and $path.StartsWith($Folder, [StringComparison]::OrdinalIgnoreCase))) { $out += $p }
        }
    }
    return $out
}

function Test-ZurgRunning {
    param($Config)
    return (@(Get-PpgProcessesUnder -Name 'zurg' -Folder $Config.ZurgDir).Count -gt 0)
}

function Test-PpgMountReady {
    param($Config)
    $movies = $Config.Libraries | Select-Object -First 1
    return (Test-Path -LiteralPath (Get-PpgLibraryPath -Config $Config -Library $movies))
}

function Wait-PpgMount {
    param($Config, [int]$TimeoutSec = 120)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-PpgMountReady -Config $Config) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Start-PpgZurg {
    param($Config)
    if (Test-ZurgRunning -Config $Config) { return }
    $exe = Join-Path $Config.ZurgDir 'zurg.exe'
    if (-not (Test-Path -LiteralPath $exe)) { throw "zurg is not installed at $exe. Run: ppg install" }
    New-Item -ItemType Directory -Force -Path $Config.LogDir | Out-Null
    Start-Process -FilePath $exe -WorkingDirectory $Config.ZurgDir -WindowStyle Hidden | Out-Null
}

function Stop-PpgZurg {
    param($Config)
    # rclone is zurg's child and holds the mount; stop both.
    foreach ($p in @(Get-PpgProcessesUnder -Name @('zurg', 'rclone') -Folder $Config.ZurgDir)) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
}

function Test-JellyfinRunning {
    return (@(Get-Process -Name 'jellyfin' -ErrorAction SilentlyContinue).Count -gt 0)
}

function Start-PpgJellyfin {
    $jf = Get-JellyfinInstall
    if (Test-JellyfinRunning) { return }
    if ($jf.ServiceType -ne 'None') {
        Write-PpgWarn "Jellyfin is installed as a Windows service ($($jf.ServiceType)). A service cannot see the debrid drive. Reinstall Jellyfin without the service option."
    }
    if (Test-Path -LiteralPath $jf.TrayExe) {
        Start-Process -FilePath $jf.TrayExe | Out-Null
    } elseif (Test-Path -LiteralPath $jf.ServerExe) {
        $argList = @()
        if ($jf.DataFolder) { $argList = @('--datadir', "`"$($jf.DataFolder)`"") }
        Start-Process -FilePath $jf.ServerExe -ArgumentList $argList -WindowStyle Hidden | Out-Null
    } else {
        throw 'Jellyfin is not installed. Run: ppg install'
    }
}

function Stop-PpgJellyfin {
    foreach ($n in @('Jellyfin.Windows.Tray', 'jellyfin')) {
        foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---- start at logon -------------------------------------------------------
# A WinFsp mount only exists inside the desktop session that created it, so
# everything starts from the Startup folder (no admin needed, no service).

function Get-PpgStartupLink {
    return (Join-Path ([Environment]::GetFolderPath('Startup')) 'PPG Movie Night.lnk')
}

function Install-PpgStartup {
    param($Config)
    New-Item -ItemType Directory -Force -Path $Config.InstallRoot | Out-Null
    $vbs = Join-Path $Config.InstallRoot 'start-hidden.vbs'
    $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$(Join-Path $Config.Root 'ppg.ps1')"" start"
    $line = 'CreateObject("WScript.Shell").Run "' + ($cmd -replace '"', '""') + '", 0, False'
    Set-Content -LiteralPath $vbs -Value $line -Encoding ASCII
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut((Get-PpgStartupLink))
    $link.TargetPath = 'wscript.exe'
    $link.Arguments = "//B ""$vbs"""
    $link.WorkingDirectory = $Config.Root
    $link.Description = 'Starts the PPG Movie Night host (debrid mount and Jellyfin) at logon'
    $link.Save()
}

function Uninstall-PpgStartup {
    Remove-Item -LiteralPath (Get-PpgStartupLink) -Force -ErrorAction SilentlyContinue
}

# ---- tools ----------------------------------------------------------------

function Test-WinGetAvailable {
    return [bool](Get-Command winget.exe -ErrorAction SilentlyContinue)
}

function Install-WithWinGet {
    param([string]$Id)
    & winget.exe install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements
    return ($LASTEXITCODE -eq 0)
}

function Test-WinFspInstalled {
    return ((Test-Path "${env:ProgramFiles(x86)}\WinFsp") -or (Test-Path "$env:ProgramFiles\WinFsp"))
}

# Real-Debrid says who this token belongs to and when premium ends.
function Get-RdUser {
    param([string]$Token)
    return Invoke-RestMethod -Uri 'https://api.real-debrid.com/rest/1.0/user' `
        -Headers @{ Authorization = "Bearer $Token" } -TimeoutSec 30 -ErrorAction Stop
}

function Get-ZurgToken {
    param($Config)
    $file = Join-Path $Config.ZurgDir 'config.yml'
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $m = Select-String -LiteralPath $file -Pattern '^\s*token:\s*(\S+)' | Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value.Trim('"', "'") }
    return $null
}

function Get-ZurgReleaseUrl {
    param([string]$Version)
    $fallback = $null
    try {
        $api = 'https://api.github.com/repos/debridmediamanager/zurg-public/releases/latest'
        if ($Version) { $api = "https://api.github.com/repos/debridmediamanager/zurg-public/releases/tags/$Version" }
        $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'ppg-streamer' } -TimeoutSec 30 -ErrorAction Stop
        $asset = @($rel.assets | Where-Object { $_.name -match 'windows-amd64\.zip$' }) | Select-Object -First 1
        if ($asset) { return $asset.browser_download_url }
        $fallback = $rel.tag_name
    } catch { }
    if (-not $fallback) { $fallback = $Version }
    if (-not $fallback) { $fallback = 'v1.0.0' }
    return "https://github.com/debridmediamanager/zurg-public/releases/download/$fallback/zurg-$fallback-windows-amd64.zip"
}
