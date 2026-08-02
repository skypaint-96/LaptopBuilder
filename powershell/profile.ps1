# Cross-platform PowerShell profile managed by arch-workstation.

if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
}

foreach ($moduleName in 'posh-git', 'Terminal-Icons') {
    if (Get-Module -ListAvailable -Name $moduleName) {
        Import-Module $moduleName
    }
}

function ll {
    Get-ChildItem -Force @args
}

function which {
    param([Parameter(Mandatory, Position = 0)][string] $Name)
    Get-Command $Name -ErrorAction Stop
}

$localProfile = Join-Path $HOME '.config/powershell/profile.local.ps1'
if (Test-Path -LiteralPath $localProfile) {
    . $localProfile
}
