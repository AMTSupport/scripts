<#
.SYNOPSIS
    Disables Adobe Acrobat Reader DC Updater and Upgrade button.

.DESCRIPTION
    The Updater service is stopped and disabled.
    A Registry key is added to prevent adobe from automatically updating to the 64-bit version.
    A Registry key is added to prevent the upgrade button from appearing if the user has a license for Acrobat Pro.

.INPUTS
    None

.OUTPUTS
    None

.EXAMPLE
    ```
    ./Disable-AdobeUpdater.ps1
    ```
#>

[CmdletBinding()]
param()

Import-Module $PSScriptRoot/../common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    Invoke-EnsureAdministrator;

    $Private:ServiceName = 'AdobeARMservice'
    if (Get-Service -Name $Private:ServiceName -ErrorAction SilentlyContinue) {
        $null = Stop-Service -Name $Private:ServiceName -Force;
        $null = Set-Service -Name $Private:ServiceName -StartupType Disabled;
    }

    $Private:RegistryPath = 'HKLM:\SOFTWARE\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown';
    Set-RegistryKey -Path:$Private:RegistryPath -Key:'bUpdater' -Value:0 -Kind DWord; # Disable Updater
    Set-RegistryKey -Path:$Private:RegistryPath -Key:'bUpdateToSingleApp' -Value:0 -Kind DWord; # Disable Updating to 64-bit version
    Set-RegistryKey -Path:$Private:RegistryPath -Key:'bEnablePersistentButton' -Value:0 -Kind DWord; # Disable Upgrade button if user has license for Acrobat Pro

    $Private:RegistryPath = $Private:RegistryPath -replace 'Policies', 'WOW6432Node\Policies';
    Set-RegistryKey -Path:$Private:RegistryPath -Key:'bUpdater' -Value:0 -Kind DWord; # Disable Updater
    Set-RegistryKey -Path:$Private:RegistryPath -Key:'bUpdateToSingleApp' -Value:0 -Kind DWord; # Disable Updating to 64-bit version
    Set-RegistryKey -Path:$Private:RegistryPath -Key:'bEnablePersistentButton' -Value:0 -Kind DWord; # Disable Upgrade button if user has license for Acrobat Pro
};
