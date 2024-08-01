#Requires -Version 5.1;
#Requires -Modules @{ModuleName='PSReadLine';RequiredVersion='2.3.5'};

Using namespace System.Management.Automation

Using module ../src/common/Environment.psm1
Using module ../src/common/Logging.psm1
Using module ../src/common/Exit.psm1
Using module ../src/common/Input.psm1

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
    Invoke-Info "Hello, $Name!";

    # Random comment
    $Restart = Get-UserConfirmation 'Restart' 'Do you want to restart the script?';
    if ($Restart) {
        Restart-Script; # Comment at the end of a line!!
    } else {
        Invoke-Info 'Exiting script...';
    };
}
