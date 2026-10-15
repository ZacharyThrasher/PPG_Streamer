# ppg: one entry point for the host stack.
#   ppg install | start | stop | status | doctor | scan | bootstrap | uninstall
# Other features add commands by dropping a script into scripts\commands\.
param(
    [Parameter(Position = 0)][string]$Command = 'help',
    [Parameter(ValueFromRemainingArguments = $true)]$Rest
)
$ErrorActionPreference = 'Stop'
$commandsDir = Join-Path $PSScriptRoot 'scripts/commands'

# Turns "-Name value -Flag" into a hashtable so it can be splatted by name.
function ConvertTo-ArgHash {
    param($Tokens)
    $h = @{}
    $list = @($Tokens | Where-Object { $null -ne $_ })
    for ($i = 0; $i -lt $list.Count; $i++) {
        $t = [string]$list[$i]
        if ($t -match '^-{1,2}(\w+)$') {
            $name = $Matches[1]
            if (($i + 1) -lt $list.Count -and -not ([string]$list[$i + 1]).StartsWith('-')) {
                $h[$name] = $list[$i + 1]; $i++
            } else {
                $h[$name] = $true
            }
        } else {
            throw "Unexpected argument '$t'. Options look like: -Name value"
        }
    }
    return $h
}

function Show-PpgHelp {
    Write-Host ''
    Write-Host 'PPG Movie Streamer host commands' -ForegroundColor Cyan
    Write-Host ''
    Get-ChildItem -Path $commandsDir -Filter '*.ps1' | Sort-Object Name | ForEach-Object {
        $first = (Get-Content -LiteralPath $_.FullName -TotalCount 1)
        $desc = ($first -replace '^#\s*', '')
        '  {0,-11} {1}' -f $_.BaseName, ($desc -replace '^ppg \w+:\s*', '')
    }
    Write-Host ''
    Write-Host 'Example: ppg install'
    Write-Host ''
}

if ($Command -in @('help', '-h', '--help', '/?')) { Show-PpgHelp; exit 0 }

$file = Join-Path $commandsDir ($Command + '.ps1')
if (-not (Test-Path -LiteralPath $file)) {
    Write-Host "Unknown command '$Command'." -ForegroundColor Red
    Show-PpgHelp
    exit 1
}
$splat = ConvertTo-ArgHash -Tokens $Rest
& $file @splat
if ($LASTEXITCODE) { exit $LASTEXITCODE }
