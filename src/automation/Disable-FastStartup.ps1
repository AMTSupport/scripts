<#
.SYNOPSIS
    Disables Windows Fast Boot, also known as Hiberboot or Fast Startup.
.DESCRIPTION
    In this day and age, realistically Fast Boot causes more issues than it solves,
    the time saving is less than a matter of seconds.
    Disabling Fast Boot will keep the system healther and more reliable in day to day use.
.EXAMPLE
    Invoke-DisableFastStartup
.OUTPUTS
    None
.NOTES
    This script requires administrative privileges to run and will exit without them.
    This script is idempotent, it can be run multiple times without causing issues.
.FUNCTIONALITY
    System, Windows, Power, Boot
#>

Import-Module $PSScriptRoot/../common/Environment.psm1;
Invoke-RunMain $PSCmdlet {
    Invoke-EnsureAdministrator;

    Set-RegistryKey `
        -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' `
        -Key 'HiberbootEnabled' `
        -Value 0 `
        -Kind DWord;
};
