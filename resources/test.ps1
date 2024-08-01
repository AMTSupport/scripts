#Requires -Version 5.1;
#Requires -Modules @{ModuleName='PSReadLine';RequiredVersion='2.3.5'};

Using namespace System.Management.Automation

Using module ../src/common/00-Environment.psm1
Using module ../src/common/01-Logging.psm1
Using module ../src/common/02-Exit.psm1
Using module ../src/common/50-Input.psm1

Using module 'PSWindowsUpdate'

<#
    Making some random documentation for the module here!!
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$Name
)

Set-StrictMode -Version 3;

Invoke-RunMain $PSCmdlet {
    Write-Output 'Hello, World!';
    Invoke-Info 'This is an info message!';

    # Random comment
    $Restart = Get-UserConfirmation 'Restart' 'Do you want to restart the script?';
    if ($Restart) {
        Restart-Script; # Comment at the end of a line!!
    } else {
        Invoke-Info 'Exiting script...';
    };
}
