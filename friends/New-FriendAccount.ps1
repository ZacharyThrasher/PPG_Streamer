<#
.SYNOPSIS
  Create (or re-apply defaults to) a friend's Jellyfin account and print a ready-to-paste invite.

.DESCRIPTION
  Run this on the host PC, once per friend. For each name it:
    1. creates the Jellyfin user (or finds the existing one),
    2. generates an easy-to-type passphrase for a new user (or when -ResetPassword is given),
    3. applies friend-safe defaults: no admin, no delete/download/convert, no Live TV,
       SyncPlay join access, Direct Play friendly (no bitrate cap unless you ask for one),
       English audio and subtitles only when the film is not in English,
    4. logs in as the friend to prove the password works, the right libraries show up and
       SyncPlay is reachable,
    5. fills friends\invite-template.txt and prints it (and copies it to the clipboard).

  Works on Windows PowerShell 5.1 and PowerShell 7+. Only talks to the Jellyfin HTTP API.
  Passwords are shown once, on screen, and are never written to disk.

.PARAMETER Name
  One or more usernames to create, for example: -Name Sam,Alex

.PARAMETER ServerUrl
  Where THIS script reaches Jellyfin. Default: $env:JELLYFIN_URL, else http://localhost:8096

.PARAMETER PublicUrl
  The address friends type. Default: $env:JELLYFIN_PUBLIC_URL, else -ServerUrl.
  With Tailscale this is the https://<pc>.<tailnet>.ts.net address from remote-access\.

.PARAMETER ApiKey
  Jellyfin API key (Dashboard > API Keys). Default: $env:JELLYFIN_API_KEY.
  If neither is set the script asks for your admin username and password instead.

.PARAMETER Library
  Library names friends may see, for example: -Library Movies. Default: every library,
  including ones added later.

.PARAMETER MaxBitrateMbps
  Per-friend streaming cap in Mbit/s. Default 0 = no cap, so Direct Play stays possible.
  A cap forces a server transcode whenever the file is bigger than the cap, and SyncPlay
  behaves best when everyone Direct Plays. Set one only if your upload cannot carry
  (friends x file bitrate).

.PARAMETER AllowCreateGroups
  Let this friend start SyncPlay groups. Default is join-only, so there is exactly one
  group per movie night (yours).

.PARAMETER AudioLanguage
  Preferred audio language as a three-letter code. Default eng.

.PARAMETER SubtitleLanguage
  Preferred subtitle language as a three-letter code. Default eng.

.PARAMETER InviteLink
  Optional Tailscale invite link, one per name. Fills the Tailscale block of the invite.
  Leave out when friends reach Jellyfin without Tailscale (for example the Caddy option).

.PARAMETER InviteTemplate
  Path to the invite message template. Default: invite-template.txt next to this script.

.PARAMETER ResetPassword
  For an existing user: generate a new password and show it.

.PARAMETER NoClipboard
  Do not copy the invite text to the clipboard.

.EXAMPLE
  .\New-FriendAccount.ps1 -Name Sam,Alex -PublicUrl https://pc.tail1234.ts.net

.EXAMPLE
  .\New-FriendAccount.ps1 -Name Sam -InviteLink https://login.tailscale.com/uinv/abc -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]]$Name,

    [string]$ServerUrl = $(if ($env:JELLYFIN_URL) { $env:JELLYFIN_URL } else { 'http://localhost:8096' }),
    [string]$PublicUrl = $env:JELLYFIN_PUBLIC_URL,
    [string]$ApiKey = $env:JELLYFIN_API_KEY,
    [string[]]$Library,
    [double]$MaxBitrateMbps = 0,
    [switch]$AllowCreateGroups,
    [string]$AudioLanguage = 'eng',
    [string]$SubtitleLanguage = 'eng',
    [string[]]$InviteLink,
    [string]$InviteTemplate = (Join-Path $PSScriptRoot 'invite-template.txt'),
    [switch]$ResetPassword,
    [switch]$NoClipboard
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# powershell.exe -File passes "a,b" as one string; accept both spellings.
function Split-List([string[]]$Values) {
    @($Values | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
$Name = Split-List $Name
if ($Library) { $Library = Split-List $Library }
if ($InviteLink) { $InviteLink = Split-List $InviteLink }

$ServerUrl = $ServerUrl.TrimEnd('/')
if (-not $PublicUrl) { $PublicUrl = $ServerUrl }
$PublicUrl = $PublicUrl.TrimEnd('/')

if ($InviteLink -and $InviteLink.Count -ne $Name.Count) {
    throw "-InviteLink needs one link per -Name ($($Name.Count) names, $($InviteLink.Count) links). Tailscale invites are single-use."
}
if ($MaxBitrateMbps -lt 0) { throw '-MaxBitrateMbps cannot be negative.' }
foreach ($n in $Name) {
    if ($n -notmatch '^[A-Za-z0-9._-]{1,40}$') {
        throw "Username '$n' has characters that are awkward to type. Use letters, digits, dot, dash or underscore (max 40)."
    }
}

# ---------- helpers ----------

$script:AuthHeader = $null

function Set-AuthToken([string]$Token) {
    $script:AuthHeader = 'MediaBrowser Client="PPG Friend Onboarding", Device="Host PC", DeviceId="ppg-friend-onboarding", Version="1.0", Token="' + $Token + '"'
}

function Invoke-Jf {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        $Body = $null,
        [string]$Token = $null,
        [switch]$Anonymous
    )
    $headers = @{}
    if ($Token) {
        $headers['Authorization'] = 'MediaBrowser Client="PPG Friend Onboarding", Device="Host PC", DeviceId="ppg-friend-check", Version="1.0", Token="' + $Token + '"'
    }
    elseif ($Anonymous) {
        $headers['Authorization'] = 'MediaBrowser Client="PPG Friend Onboarding", Device="Host PC", DeviceId="ppg-friend-check", Version="1.0"'
    }
    else {
        $headers['Authorization'] = $script:AuthHeader
    }
    $req = @{
        Uri         = $ServerUrl + $Path
        Method      = $Method
        Headers     = $headers
        ContentType = 'application/json'
    }
    if ($null -ne $Body) {
        $req['Body'] = [System.Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 10 -Compress))
    }
    Invoke-RestMethod @req
}

# Windows PowerShell 5.1 hands JSON arrays back as one object, PowerShell 7 unrolls them.
# Piping through ForEach-Object makes both look the same.
function ConvertTo-List($Value) {
    if ($null -eq $Value) { return @() }
    @($Value | ForEach-Object { $_ })
}

function Set-Prop($Object, [string]$Prop, $Value) {
    if ($Object.PSObject.Properties[$Prop]) { $Object.$Prop = $Value }
    else { $Object | Add-Member -NotePropertyName $Prop -NotePropertyValue $Value }
}

# 256 short, common, easy-to-spell words -> 4 words = 32 bits. Jellyfin locks the account
# after a few wrong guesses, so this is plenty for a movie club and far easier to type
# than random characters.
$script:Words = @(
 'acorn','amber','anchor','apple','arrow','aspen','atlas','badge','bacon','banjo','barn','basil','beach','berry','birch','bison',
 'blaze','bloom','boat','bolt','bonus','brave','bread','brick','brook','cabin','cable','camel','candy','canoe','cargo','cedar',
 'chair','chalk','charm','chess','chill','cider','cliff','cloud','clove','coast','cobra','cocoa','comet','coral','couch','crane',
 'creek','crisp','crown','daisy','dance','delta','denim','diner','disco','dizzy','dodge','donut','dragon','dream','drift','drum',
 'eagle','earth','ember','entry','fable','fancy','feast','fern','ferry','fiddle','field','finch','flame','flute','focus','forest',
 'fox','frost','fudge','galaxy','garden','gecko','giant','ginger','glider','globe','goose','grape','gravy','grove','guitar','habit',
 'harbor','hazel','heron','hobby','honey','hover','humble','icing','igloo','image','index','inlet','iris','ivory','jacket','jelly',
 'jewel','jolly','judge','juice','kayak','kebab','kettle','kiosk','kite','koala','label','lagoon','lamp','lemon','lilac','linen',
 'lizard','lotus','lucky','lunar','magic','mango','maple','marble','meadow','melon','mint','mocha','motor','mural','nacho','navy',
 'nest','noble','noodle','novel','oasis','ocean','olive','onion','opal','orbit','otter','oven','paddle','panda','paper','peach',
 'pearl','pepper','piano','pilot','pixel','pizza','planet','plum','pocket','polar','poppy','pretzel','pumpkin','puzzle','quail','quartz',
 'quilt','rabbit','radio','raven','river','robin','rocket','salad','salmon','sandy','scarf','shell','silver','sketch','sled','spark',
 'spice','spruce','stone','sunny','tablet','tango','teapot','thistle','tiger','toast','topaz','trail','tulip','turtle','umber','union',
 'velvet','violet','vivid','waffle','walnut','whale','willow','window','winter','wizard','yacht','yellow','yodel','zebra','zesty','zinc',
 'apron','bagel','bench','bingo','cactus','cherry','cobalt','dune','echo','elbow','fjord','flint','gadget','harp','hockey','jungle',
 'kiwi','lantern','mosaic','nutmeg','orchid','pebble','pickle','quiver','ripple','saddle','tundra','velcro','walrus','yarn','zipper','bubble'
)

function New-Passphrase {
    if ($script:Words.Count -ne 256) { throw 'Word list must have exactly 256 entries.' }
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $bytes = New-Object byte[] 4
        $rng.GetBytes($bytes)
    }
    finally { $rng.Dispose() }
    $picked = foreach ($b in $bytes) { $script:Words[[int]$b % $script:Words.Count] }
    ($picked -join '-')
}

# ---------- connect + authenticate as the host ----------

try {
    $info = Invoke-Jf -Method GET -Path '/System/Info/Public' -Anonymous
}
catch {
    throw "Cannot reach Jellyfin at $ServerUrl ($($_.Exception.Message)). Is the server running? Use -ServerUrl if it is not on this PC's port 8096."
}
Write-Host "Jellyfin $($info.Version) at $ServerUrl" -ForegroundColor Cyan

if ($ApiKey) {
    Set-AuthToken $ApiKey
}
else {
    Write-Host 'No API key given. Sign in as the Jellyfin admin (nothing is stored).' -ForegroundColor Yellow
    $adminName = Read-Host 'Admin username'
    $adminPw = Read-Host 'Admin password' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPw)
    try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    $auth = Invoke-Jf -Method POST -Path '/Users/AuthenticateByName' -Anonymous -Body @{ Username = $adminName; Pw = $plain }
    $plain = $null
    Set-AuthToken $auth.AccessToken
}

try { $null = Invoke-Jf -Method GET -Path '/Users' }
catch { throw "Jellyfin rejected the credentials, or the account is not an administrator. ($($_.Exception.Message))" }

# ---------- libraries ----------

$folders = ConvertTo-List (Invoke-Jf -Method GET -Path '/Library/VirtualFolders')
$enabledFolderIds = @()
$allFolders = $true
if ($Library) {
    $allFolders = $false
    foreach ($l in $Library) {
        $hit = $folders | Where-Object { $_.Name -eq $l } | Select-Object -First 1
        if (-not $hit) {
            $names = ($folders | ForEach-Object { $_.Name }) -join ', '
            throw "No library named '$l'. Libraries on this server: $names"
        }
        $enabledFolderIds += [string]$hit.ItemId
    }
}
if ($folders.Count -eq 0) {
    Write-Warning 'This server has no libraries yet. Accounts are still created; add a library before movie night.'
}

# ---------- template ----------

$template = $null
if (Test-Path -LiteralPath $InviteTemplate) {
    $template = Get-Content -LiteralPath $InviteTemplate -Raw -Encoding UTF8
}
else {
    Write-Warning "Invite template not found at $InviteTemplate. Accounts will be created but no invite text will be printed."
}

function Format-Invite([string]$Text, [string]$User, [string]$Pass, [string]$Link) {
    # Optional blocks: [[tailscale]] ... [[/tailscale]] kept only when an invite link exists.
    if ($Link) {
        $Text = $Text -replace '(?s)\[\[tailscale\]\]\r?\n?', '' -replace '(?s)\[\[/tailscale\]\]\r?\n?', ''
    }
    else {
        $Text = [regex]::Replace($Text, '(?s)\[\[tailscale\]\].*?\[\[/tailscale\]\]\r?\n?', '')
    }
    $Text.Replace('{NAME}', $User).Replace('{URL}', $PublicUrl).Replace('{USER}', $User).Replace('{PASSWORD}', $Pass).Replace('{INVITE_LINK}', $Link).TrimEnd()
}

# ---------- per friend ----------

$existing = ConvertTo-List (Invoke-Jf -Method GET -Path '/Users')
$results = @()
$i = -1

foreach ($friend in $Name) {
    $i++
    $link = ''
    if ($InviteLink) { $link = $InviteLink[$i] }

    $user = $existing | Where-Object { $_.Name -ieq $friend } | Select-Object -First 1
    $password = $null
    $created = $false

    if (-not $user) {
        if (-not $PSCmdlet.ShouldProcess("$ServerUrl", "Create Jellyfin user '$friend'")) { continue }
        $password = New-Passphrase
        $user = Invoke-Jf -Method POST -Path '/Users/New' -Body @{ Name = $friend; Password = $password }
        $created = $true
    }
    elseif ($ResetPassword) {
        if (-not $PSCmdlet.ShouldProcess("$ServerUrl", "Reset password for existing user '$friend'")) { continue }
        $password = New-Passphrase
        $null = Invoke-Jf -Method POST -Path ('/Users/' + $user.Id + '/Password') -Body @{ NewPw = $password; ResetPassword = $false }
        # The endpoint above sets the password for a user that already has one only when the current password
        # is supplied or the caller is an admin; admins can set it directly.
    }
    else {
        if (-not $PSCmdlet.ShouldProcess("$ServerUrl", "Re-apply friend defaults to existing user '$friend' (password unchanged)")) { continue }
    }

    $friend = $user.Name   # keep the server's spelling for the invite

    # Policy: read the full object, change only what we care about, send it all back.
    $full = Invoke-Jf -Method GET -Path ('/Users/' + $user.Id)
    $p = $full.Policy
    Set-Prop $p 'IsAdministrator' $false
    Set-Prop $p 'IsHidden' $true
    Set-Prop $p 'IsDisabled' $false
    Set-Prop $p 'EnableRemoteControlOfOtherUsers' $false
    Set-Prop $p 'EnableLiveTvAccess' $false
    Set-Prop $p 'EnableLiveTvManagement' $false
    Set-Prop $p 'EnableContentDeletion' $false
    Set-Prop $p 'EnableContentDownloading' $false
    Set-Prop $p 'EnableSyncTranscoding' $false
    Set-Prop $p 'EnableMediaConversion' $false
    Set-Prop $p 'EnablePublicSharing' $false
    Set-Prop $p 'EnableCollectionManagement' $false
    Set-Prop $p 'EnableSubtitleManagement' $false
    Set-Prop $p 'EnableMediaPlayback' $true
    # Transcoding stays allowed as a safety net (browser fallback, Dolby Vision, weak connections);
    # remuxing stays on so Direct Stream works. Direct Play is favoured by NOT capping the bitrate.
    Set-Prop $p 'EnableAudioPlaybackTranscoding' $true
    Set-Prop $p 'EnableVideoPlaybackTranscoding' $true
    Set-Prop $p 'EnablePlaybackRemuxing' $true
    Set-Prop $p 'RemoteClientBitrateLimit' ([int64][math]::Round($MaxBitrateMbps * 1000000))
    Set-Prop $p 'LoginAttemptsBeforeLockout' 5
    Set-Prop $p 'EnableAllFolders' $allFolders
    Set-Prop $p 'EnabledFolders' @($enabledFolderIds)
    if ($AllowCreateGroups) { Set-Prop $p 'SyncPlayAccess' 'CreateAndJoinGroups' }
    else { Set-Prop $p 'SyncPlayAccess' 'JoinGroups' }
    $null = Invoke-Jf -Method POST -Path ('/Users/' + $user.Id + '/Policy') -Body $p

    # Preferences: films are mostly English; show subtitles only when the audio is something else.
    $c = $full.Configuration
    Set-Prop $c 'AudioLanguagePreference' $AudioLanguage
    Set-Prop $c 'SubtitleLanguagePreference' $SubtitleLanguage
    Set-Prop $c 'SubtitleMode' 'Smart'
    Set-Prop $c 'PlayDefaultAudioTrack' $true
    Set-Prop $c 'RememberAudioSelections' $true
    Set-Prop $c 'RememberSubtitleSelections' $true
    Set-Prop $c 'EnableNextEpisodeAutoPlay' $false
    Set-Prop $c 'DisplayMissingEpisodes' $false
    try {
        $null = Invoke-Jf -Method POST -Path ('/Users/Configuration?userId=' + $user.Id) -Body $c
    }
    catch {
        # Jellyfin 10.8 and older only know the path-style endpoint.
        $null = Invoke-Jf -Method POST -Path ('/Users/' + $user.Id + '/Configuration') -Body $c
    }

    # Self-check, as the friend. Only possible when we know the password.
    $check = 'skipped (existing user, password unchanged)'
    if ($password) {
        try {
            $login = Invoke-Jf -Method POST -Path '/Users/AuthenticateByName' -Anonymous -Body @{ Username = $friend; Pw = $password }
            $tok = $login.AccessToken
            $views = Invoke-Jf -Method GET -Path '/UserViews' -Token $tok
            $viewNames = ConvertTo-List ($views.Items | ForEach-Object { $_.Name })
            $null = Invoke-Jf -Method GET -Path '/SyncPlay/List' -Token $tok
            $check = 'ok: can log in, sees [' + ($viewNames -join ', ') + '], SyncPlay reachable'
            try { $null = Invoke-Jf -Method POST -Path '/Sessions/Logout' -Token $tok } catch { }
        }
        catch {
            $check = 'FAILED: ' + $_.Exception.Message
        }
    }

    $action = 'updated'
    if ($created) { $action = 'created' }
    Write-Host ''
    Write-Host ("[{0}] {1}  ({2})" -f $friend, $action, $check) -ForegroundColor Green

    $invite = $null
    if ($password -and $template) {
        $invite = Format-Invite -Text $template -User $friend -Pass $password -Link $link
        Write-Host '----- paste this to the friend -----' -ForegroundColor Cyan
        Write-Host $invite
        Write-Host '------------------------------------' -ForegroundColor Cyan
        if (-not $NoClipboard -and $Name.Count -eq 1 -and (Get-Command Set-Clipboard -ErrorAction SilentlyContinue)) {
            try { Set-Clipboard -Value $invite; Write-Host '(copied to clipboard)' -ForegroundColor DarkGray } catch { }
        }
    }
    elseif (-not $password) {
        Write-Host 'Existing account: defaults re-applied. Use -ResetPassword to issue a new password and invite.' -ForegroundColor DarkGray
    }

    $results += [pscustomobject]@{
        Name     = $friend
        Action   = $action
        Password = $password
        SelfTest = $check
    }
}

Write-Host ''
Write-Host 'Done. Passwords above are not stored anywhere; copy them now.' -ForegroundColor Yellow
if ($results | Where-Object { $_.SelfTest -like 'FAILED*' }) {
    Write-Warning 'At least one self-check failed. See the line marked FAILED above.'
    exit 1
}
