#Requires -RunAsAdministrator

Using module ../../../Output/PowerShellModules/AMT.PowerShell.Common/AMT.PowerShell.Common.psd1
Using module .\Update-ToWin11.psm1

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNull()]
    [Switch]$SkipCheck,

    [Parameter()]
    [ValidateNotNull()]
    [Switch]$CheckOnly,

    [Parameter()]
    [ValidateNotNull()]
    [Switch]$AlwaysShowResults = $CheckOnly
)

Invoke-RunMain $PSCmdlet {
    if (-not $SkipCheck -and -not (Test-CanUpgrade -AlwaysShowResults:$AlwaysShowResults) -or $CheckOnly) {
        return;
    }

    Update-ToWin11;
}
