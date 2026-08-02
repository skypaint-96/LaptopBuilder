[CmdletBinding()]
param(
    [Parameter()]
    [switch] $InstallModules
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7 or newer is required.'
}

$ScriptRoot = Split-Path -Parent $PSCommandPath
$ProfileSource = Join-Path $ScriptRoot 'profile.ps1'
$ProfileDirectory = Join-Path $HOME '.config/powershell'
$ManagedProfile = Join-Path $ProfileDirectory 'Microsoft.PowerShell_profile.ps1'
$LocalProfile = Join-Path $ProfileDirectory 'profile.local.ps1'

New-Item -ItemType Directory -Path $ProfileDirectory -Force | Out-Null

$loader = @"
# Managed by arch-workstation. Put personal overrides in $LocalProfile.
. '$ProfileSource'
"@
Set-Content -LiteralPath $ManagedProfile -Value $loader -Encoding utf8NoBOM

if ($InstallModules) {
    $moduleFile = Join-Path $ScriptRoot 'modules.txt'
    foreach ($name in Get-Content -LiteralPath $moduleFile) {
        $name = $name.Trim()
        if ([string]::IsNullOrWhiteSpace($name) -or $name.StartsWith('#')) {
            continue
        }

        if (-not (Get-Module -ListAvailable -Name $name)) {
            Write-Host "Installing PowerShell module: $name"
            Install-Module -Name $name -Repository PSGallery -Scope CurrentUser -Force -AllowClobber
        }
    }
}

Write-Host "PowerShell profile configured at $ManagedProfile"
