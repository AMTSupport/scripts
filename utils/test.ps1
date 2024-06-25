
Using namespace System.Management.Automation
Using module ../src/common/00-Environment.psm1
Using module @{
    ModuleName      = 'PSReadLine';
    RequiredVersion = '2.3.5';
}

<#
    Making some random documentation for the module here!!
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$Name
)

Set-StrictMode -Version 3;

Import-Module $PSScriptRoot/../src/common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    Write-Host 'Hello, World!';

    # Write-Error 'This is an error message!' -Category InvalidOperation;
    Invoke-FailedExit 1050;

    # Random comment
    $Restart = Get-UserConfirmation 'Restart' 'Do you want to restart the script?';
    if ($Restart) {
        Write-Host 'Restarting script...';
        Restart-Script; # Comment at the end of a line!!
    }
    else {
        Write-Host 'Exiting script...';
    };
}
