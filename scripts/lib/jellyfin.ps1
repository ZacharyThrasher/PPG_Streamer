# Jellyfin REST helpers and the idempotent bootstrap. Dot-source after common.ps1.
# Safe to run repeatedly: it re-applies the settings every time.

$script:Jf = @{ Url = $null; Token = $null }

function Connect-Jellyfin {
    param([Parameter(Mandatory)][string]$Url, [string]$Token)
    $script:Jf.Url = $Url.TrimEnd('/')
    $script:Jf.Token = $Token
}

function Get-JfAuthHeader {
    $h = 'MediaBrowser Client="PPG", Device="PPG Host", DeviceId="ppg-host", Version="1.0.0"'
    if ($script:Jf.Token) { $h += ', Token="' + $script:Jf.Token + '"' }
    return $h
}

function Get-HttpErrorBody {
    param($ErrorRecord)
    try {
        if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
            return $ErrorRecord.ErrorDetails.Message
        }
        $resp = $ErrorRecord.Exception.Response
        if ($resp) {
            $stream = $resp.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            return $reader.ReadToEnd()
        }
    } catch { }
    return ''
}

# Calls the Jellyfin API. -Body can be an object (sent as JSON) or a ready JSON string.
function Invoke-Jf {
    param(
        [string]$Method = 'GET',
        [Parameter(Mandatory)][string]$Path,
        $Body,
        [string[]]$Query
    )
    $uri = $script:Jf.Url + $Path
    if ($Query -and $Query.Count -gt 0) { $uri += '?' + ($Query -join '&') }
    $req = @{
        Uri         = $uri
        Method      = $Method
        Headers     = @{ Authorization = (Get-JfAuthHeader) }
        TimeoutSec  = 60
        ErrorAction = 'Stop'
    }
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        if ($Body -is [string]) { $json = $Body } else { $json = $Body | ConvertTo-Json -Depth 20 }
        $req.Body = [System.Text.Encoding]::UTF8.GetBytes($json)
        $req.ContentType = 'application/json; charset=utf-8'
    }
    if ((Get-Command Invoke-RestMethod).Parameters.ContainsKey('UseBasicParsing')) {
        $req.UseBasicParsing = $true
    }
    $attempt = 0
    while ($true) {
        try {
            $result = Invoke-RestMethod @req
            break
        } catch {
            $attempt++
            $detail = Get-HttpErrorBody -ErrorRecord $_
            # 503 means the server is still starting; wait and retry.
            if ($attempt -lt 30 -and $_.Exception.Message -match '503') {
                Start-Sleep -Seconds 2
                continue
            }
            $detail = ($detail -replace '<[^>]+>', ' ' -replace '\s+', ' ').Trim()
            if ($detail.Length -gt 300) { $detail = $detail.Substring(0, 300) }
            throw "Jellyfin API $Method $Path failed: $($_.Exception.Message) $detail"
        }
    }
    # Windows PowerShell 5.1 returns a JSON array as one object; hand back the items.
    foreach ($item in $result) { $item }
}

function ConvertTo-UrlValue {
    # URL-escape one query value.
    param([string]$Value)
    return [uri]::EscapeDataString($Value)
}

function Set-JfProp {
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

# Waits until the server answers. Returns the public info object.
function Wait-Jellyfin {
    param([int]$TimeoutSec = 180)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $last = ''
    while ((Get-Date) -lt $deadline) {
        try {
            $info = Invoke-RestMethod -Uri ($script:Jf.Url + '/System/Info/Public') -TimeoutSec 5 -ErrorAction Stop
            if ($info -and $info.PSObject.Properties['Version']) { return $info }
        } catch {
            $last = $_.Exception.Message
        }
        Start-Sleep -Seconds 2
    }
    throw "Jellyfin did not answer at $($script:Jf.Url) within $TimeoutSec seconds. Last error: $last"
}

# ---- first run ------------------------------------------------------------

function Initialize-JfWizard {
    param($Config, [string]$AdminPassword)
    Invoke-Jf -Method POST -Path '/Startup/Configuration' -Body @{
        ServerName                = $Config.ServerName
        UICulture                 = 'en-US'
        MetadataCountryCode       = 'US'
        PreferredMetadataLanguage = 'en'
    } | Out-Null
    # Jellyfin creates its default user lazily; this read makes the next call reliable.
    Invoke-Jf -Method GET -Path '/Startup/User' | Out-Null
    Invoke-Jf -Method POST -Path '/Startup/User' -Body @{
        Name     = $Config.AdminUser
        Password = $AdminPassword
    } | Out-Null
    Invoke-Jf -Method POST -Path '/Startup/RemoteAccess' -Body @{ EnableRemoteAccess = $true } | Out-Null
    Invoke-Jf -Method POST -Path '/Startup/Complete' | Out-Null
}

# Signs in and makes sure a long-lived API key exists. Returns the key.
function Connect-JfAdmin {
    param($Config, [string]$AdminPassword)

    $state = Get-PpgState -Config $Config
    if ($state -and $state.PSObject.Properties['ApiKey'] -and $state.ApiKey) {
        Connect-Jellyfin -Url $Config.JellyfinUrl -Token $state.ApiKey
        try {
            Invoke-Jf -Path '/System/Info' | Out-Null
            return $state.ApiKey
        } catch {
            Write-PpgWarn 'Saved API key no longer works; signing in again.'
            Connect-Jellyfin -Url $Config.JellyfinUrl
        }
    }

    $user = $Config.AdminUser
    $pw = $AdminPassword
    if (-not $pw -and $state -and $state.PSObject.Properties['AdminPassword']) { $pw = $state.AdminPassword }
    if ($state -and $state.PSObject.Properties['AdminUser'] -and $state.AdminUser) { $user = $state.AdminUser }
    if (-not $pw) {
        throw 'No saved admin login. Re-run with -AdminPassword (and set AdminUser in config) for the existing Jellyfin admin.'
    }

    $auth = Invoke-Jf -Method POST -Path '/Users/AuthenticateByName' -Body @{ Username = $user; Pw = $pw }
    Connect-Jellyfin -Url $Config.JellyfinUrl -Token $auth.AccessToken

    $appName = 'PPG-Streamer'
    $keys = Invoke-Jf -Path '/Auth/Keys'
    $mine = @($keys.Items | Where-Object { $_.AppName -eq $appName })
    if ($mine.Count -eq 0) {
        Invoke-Jf -Method POST -Path '/Auth/Keys' -Query @("app=$(ConvertTo-UrlValue $appName)") | Out-Null
        $keys = Invoke-Jf -Path '/Auth/Keys'
        $mine = @($keys.Items | Where-Object { $_.AppName -eq $appName })
    }
    $apiKey = $mine[0].AccessToken
    Save-PpgState -Config $Config -Values @{ ApiKey = $apiKey; AdminUser = $user; AdminPassword = $pw; JellyfinUrl = $Config.JellyfinUrl }
    Connect-Jellyfin -Url $Config.JellyfinUrl -Token $apiKey
    return $apiKey
}

# ---- settings -------------------------------------------------------------

# NVENC for encoding, CUDA for HDR to SDR tone mapping. Direct Play stays the
# default path (clients decide that); this is the fallback for browsers and weak clients.
function Set-JfTranscoding {
    param($Config)
    $enc = Invoke-Jf -Path '/System/Configuration/encoding'
    Set-JfProp $enc 'HardwareAccelerationType' 'nvenc'
    Set-JfProp $enc 'EnableHardwareEncoding' $true
    Set-JfProp $enc 'HardwareDecodingCodecs' @('h264', 'hevc', 'mpeg2video', 'vc1', 'vp8', 'vp9', 'av1')
    Set-JfProp $enc 'EnableDecodingColorDepth10Hevc' $true
    Set-JfProp $enc 'EnableDecodingColorDepth10Vp9' $true
    Set-JfProp $enc 'EnableEnhancedNvdecDecoder' $true
    Set-JfProp $enc 'EnableTonemapping' $true
    Set-JfProp $enc 'TonemappingAlgorithm' 'bt2390'
    Set-JfProp $enc 'TonemappingMode' 'auto'
    Set-JfProp $enc 'TonemappingRange' 'auto'
    Set-JfProp $enc 'AllowHevcEncoding' $true
    Set-JfProp $enc 'AllowAv1Encoding' $false
    Set-JfProp $enc 'EnableThrottling' $true
    Set-JfProp $enc 'EnableSegmentDeletion' $true
    if ($Config.TranscodePath) { Set-JfProp $enc 'TranscodingTempPath' $Config.TranscodePath }
    Invoke-Jf -Method POST -Path '/System/Configuration/encoding' -Body $enc | Out-Null
}

function Set-JfServerOptions {
    param($Config)
    $srv = Invoke-Jf -Path '/System/Configuration'
    Set-JfProp $srv 'ServerName' $Config.ServerName
    Set-JfProp $srv 'QuickConnectAvailable' $true
    Set-JfProp $srv 'AllowClientLogUpload' $false
    Set-JfProp $srv 'LibraryScanFanoutConcurrency' ([int]$Config.ScanConcurrency)
    Set-JfProp $srv 'LibraryMetadataRefreshConcurrency' ([int]$Config.ScanConcurrency)
    $bps = [int64]$Config.RemoteBitrateLimitMbps * 1000000
    Set-JfProp $srv 'RemoteClientBitrateLimit' $bps
    Invoke-Jf -Method POST -Path '/System/Configuration' -Body $srv | Out-Null
}

# Everything that would read whole files off the debrid mount is off.
function Set-JfLibraryOptionsSafe {
    param($Options)
    Set-JfProp $Options 'Enabled' $true
    Set-JfProp $Options 'EnableRealtimeMonitor' $false
    Set-JfProp $Options 'EnableChapterImageExtraction' $false
    Set-JfProp $Options 'ExtractChapterImagesDuringLibraryScan' $false
    Set-JfProp $Options 'EnableTrickplayImageExtraction' $false
    Set-JfProp $Options 'ExtractTrickplayImagesDuringLibraryScan' $false
    Set-JfProp $Options 'SaveTrickplayWithMedia' $false
    Set-JfProp $Options 'EnableLUFSScan' $false
    Set-JfProp $Options 'SaveLocalMetadata' $false
    Set-JfProp $Options 'SaveSubtitlesWithMedia' $false
    Set-JfProp $Options 'SaveLyricsWithMedia' $false
    Set-JfProp $Options 'AutomaticRefreshIntervalDays' 0
    return $Options
}

function Set-JfLibraries {
    param($Config)
    foreach ($lib in $Config.Libraries) {
        $path = Get-PpgLibraryPath -Config $Config -Library $lib
        $existing = @(Invoke-Jf -Path '/Library/VirtualFolders' | Where-Object { $_.Name -eq $lib.Name })
        if ($existing.Count -eq 0) {
            $query = @("name=$(ConvertTo-UrlValue $lib.Name)", "collectionType=$(ConvertTo-UrlValue $lib.Type)", "paths=$(ConvertTo-UrlValue $path)", 'refreshLibrary=false')
            $opts = Set-JfLibraryOptionsSafe -Options (New-Object PSObject)
            Invoke-Jf -Method POST -Path '/Library/VirtualFolders' -Query $query -Body @{ LibraryOptions = $opts } | Out-Null
            Write-PpgOk "Created library '$($lib.Name)' -> $path"
            $existing = @(Invoke-Jf -Path '/Library/VirtualFolders' | Where-Object { $_.Name -eq $lib.Name })
        } else {
            if ($existing[0].Locations -notcontains $path) {
                Write-PpgWarn "Library '$($lib.Name)' already exists with different folders ($($existing[0].Locations -join ', ')); leaving folders alone."
            }
        }
        $opts = Set-JfLibraryOptionsSafe -Options $existing[0].LibraryOptions
        Invoke-Jf -Method POST -Path '/Library/VirtualFolders/LibraryOptions' -Body @{ Id = $existing[0].ItemId; LibraryOptions = $opts } | Out-Null
        Write-PpgOk "Library '$($lib.Name)': scans, thumbnails and chapter images off"
    }
}

# Remove the automatic jobs that read media in bulk. Scans happen when the
# debrid library changes (zurg hook) or when you run: ppg scan
function Set-JfScheduledTasks {
    $pattern = 'Trickplay|Chapter|Segment|Normaliz|Keyframe|RefreshLibrary|Scan Media Library'
    $tasks = @(Invoke-Jf -Path '/ScheduledTasks')
    foreach ($t in $tasks) {
        $key = ''
        if ($t.PSObject.Properties['Key']) { $key = [string]$t.Key }
        if (($t.Name -match $pattern) -or ($key -match $pattern)) {
            Invoke-Jf -Method POST -Path "/ScheduledTasks/$($t.Id)/Triggers" -Body '[]' | Out-Null
            Write-PpgOk "Automatic schedule removed: $($t.Name)"
        }
    }
}

function Invoke-PpgHooks {
    param($Config, [hashtable]$Context)
    $dir = Join-Path $Config.Root 'hooks/post-bootstrap.d'
    if (-not (Test-Path $dir)) { return }
    $hooks = Get-ChildItem -Path $dir -Filter '*.ps1' | Sort-Object Name
    foreach ($h in $hooks) {
        Write-PpgInfo "Running hook $($h.Name)"
        try { & $h.FullName -Context $Context }
        catch { Write-PpgWarn "Hook $($h.Name) failed: $($_.Exception.Message)" }
    }
}

# ---- the whole thing ------------------------------------------------------

function Invoke-PpgBootstrap {
    param($Config, [string]$AdminPassword, [switch]$SkipHooks)

    Connect-Jellyfin -Url $Config.JellyfinUrl
    Write-PpgStep 'Waiting for Jellyfin'
    $info = Wait-Jellyfin
    Write-PpgOk "Jellyfin $($info.Version) is up at $($Config.JellyfinUrl)"
    if ((Compare-PpgVersion $info.Version $Config.JellyfinMinVersion) -lt 0) {
        Write-PpgWarn "Jellyfin $($info.Version) is older than $($Config.JellyfinMinVersion). SyncPlay drifts on older versions. Update Jellyfin."
    }

    if (-not $info.StartupWizardCompleted) {
        Write-PpgStep 'First-run setup'
        $pw = $AdminPassword
        if (-not $pw) { $pw = New-PpgPassword }
        Initialize-JfWizard -Config $Config -AdminPassword $pw
        Save-PpgState -Config $Config -Values @{ AdminUser = $Config.AdminUser; AdminPassword = $pw }
        Write-PpgOk "Created admin '$($Config.AdminUser)'"
        $AdminPassword = $pw
    }

    Write-PpgStep 'Signing in'
    $apiKey = Connect-JfAdmin -Config $Config -AdminPassword $AdminPassword
    Write-PpgOk 'API key ready (saved to the state file)'

    Write-PpgStep 'Transcoding: NVENC + CUDA HDR tone mapping'
    Set-JfTranscoding -Config $Config
    Write-PpgOk 'NVENC on, CUDA tone mapping on, enhanced NVDEC on'

    Write-PpgStep 'Server options'
    Set-JfServerOptions -Config $Config
    Write-PpgOk "Quick Connect on, scan concurrency $($Config.ScanConcurrency), remote cap $($Config.RemoteBitrateLimitMbps) Mbps (0 = none)"

    Write-PpgStep 'Libraries'
    Set-JfLibraries -Config $Config

    Write-PpgStep 'Scheduled jobs'
    Set-JfScheduledTasks

    if (-not $SkipHooks) {
        Write-PpgStep 'Hooks'
        Invoke-PpgHooks -Config $Config -Context @{
            Config  = $Config
            Url     = $Config.JellyfinUrl
            ApiKey  = $apiKey
            Version = $info.Version
        }
    }
}
