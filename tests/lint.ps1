# Lints every script for Windows PowerShell 5.1 compatibility and common mistakes.
# Usage: pwsh tests/lint.ps1
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
    Install-Module PSScriptAnalyzer -MaximumVersion 1.22.0 -Force -Scope CurrentUser
}
$bad = 0
foreach ($f in Get-ChildItem -Path $repo -Recurse -Include *.ps1, *.psd1 | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }) {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
    foreach ($e in $errors) { Write-Host "PARSE $($f.Name):$($e.Extent.StartLineNumber) $($e.Message)" -ForegroundColor Red; $bad++ }
}
$results = Invoke-ScriptAnalyzer -Path $repo -Recurse -Settings (Join-Path $repo 'PSScriptAnalyzerSettings.psd1')
foreach ($r in $results) { Write-Host "$($r.RuleName) $($r.ScriptName):$($r.Line) $($r.Message)" -ForegroundColor Red; $bad++ }
if ($bad -gt 0) { Write-Host "$bad problem(s)" -ForegroundColor Red; exit 1 }
Write-Host 'Lint clean' -ForegroundColor Green
