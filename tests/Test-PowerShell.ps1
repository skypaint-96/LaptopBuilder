[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$files = Get-ChildItem -LiteralPath (Join-Path $root 'powershell') -Filter '*.ps1' -File
if (-not $files) {
    throw 'No PowerShell files found.'
}

$allErrors = [System.Collections.Generic.List[string]]::new()
foreach ($file in $files) {
    $tokens = $null
    $parseErrors = $null
    [void] [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref] $tokens,
        [ref] $parseErrors
    )
    foreach ($parseError in $parseErrors) {
        $allErrors.Add("$($file.Name):$($parseError.Extent.StartLineNumber): $($parseError.Message)")
    }
}

if ($allErrors.Count -gt 0) {
    throw ($allErrors -join [Environment]::NewLine)
}

Write-Host "PowerShell parser: checked $($files.Count) file(s)."
