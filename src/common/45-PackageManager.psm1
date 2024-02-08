#Requires -Version 5.1

enum PackageManager {
    Chocolatey

    Unsupported
}

# TODO :: Add support for other package managers.
[PackageManager]$Script:PackageManager = switch ($env:OS) {
    'Windows_NT' { [PackageManager]::Chocolatey };
    default { [PackageManager]::Unsupported };
};
[HashTable]$Script:PackageManagerDetails = switch ($Script:PackageManager) {
    Chocolatey {
        @{
            Executable = "$($env:SystemDrive)\ProgramData\Chocolatey\bin\choco.exe";
            Commands = @{
                List       = 'list';
                Uninstall  = 'uninstall';
                Install    = 'install';
                Update     = 'upgrade';
            }
            Options = @{
                Common = @('--confirm', '--limit-output', '--exact');
                Force = '--force';
            }
        };
    };
    Unsupported {
        Invoke-Error 'Could not find a supported package manager.';
        $null;
    }
};

function Install-Requirements {
    @{
        PSPrefix = '📦';
        PSMessage = "Installing requirements for $Script:PackageManager...";
        PSColour = 'Green';
    } | Invoke-Write;

    switch ($Script:PackageManager) {
        Chocolatey {
            if (Get-Command -Name 'choco' -ErrorAction SilentlyContinue) {
                Invoke-Debug 'Chocolatey is already installed. Skipping installation.';
                return
            }

            if (Test-Path -Path "$($env:SystemDrive)\ProgramData\chocolatey") {
                Invoke-Debug 'Chocolatey files found, seeing if we can repair them...';
                if (Test-Path -Path "$($env:SystemDrive)\ProgramData\chocolatey\bin\choco.exe") {
                    Invoke-Debug 'Chocolatey bin found, should be able to refreshenv!';
                    Invoke-Debug 'Refreshing environment variables...';
                    Import-Module "$($env:SystemDrive)\ProgramData\chocolatey\Helpers\chocolateyProfile.psm1" -Force;
                    refreshenv | Out-Null;

                    return;
                } else {
                    Invoke-Warn 'Chocolatey bin not found, deleting folder and reinstalling...';
                    Remove-Item -Path "$($env:SystemDrive)\ProgramData\chocolatey" -Recurse -Force;
                }
            }

            Invoke-Info 'Installing Chocolatey...';
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'));
        }
        Default {}
    }
}

<#
.SYNOPSIS
    Tests if a package is installed.
.PARAMETER PackageName
    The name of the package to test.
#>
function Test-Package(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$PackageName
) {
    @{
        PSPrefix = '🔍';
        PSMessage = "Checking if package '$PackageName' is installed...";
        PSColour = 'Yellow';
    } | Invoke-Write;

    # if ($PackageVersion) {
    #     $Local:PackageArgs['Version'] = $PackageVersion;
    # }

    [Boolean]$Local:Installed = & $Script:PackageManagerDetails.Executable $Script:PackageManagerDetails.Commands.List $Script:PackageManagerDetails.Options.Common $PackageName;
    Invoke-Verbose "Package '$PackageName' is $(if (-not $Local:Installed) { 'not ' })installed.";
    return $Local:Installed;
}

function Install-ManagedPackage(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$PackageName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]$Sha256

    # [Parameter()]
    # [ValidateNotNullOrEmpty()]
    # [String]$PackageVersion
) {
    @{
        PSPrefix = '📦';
        PSMessage = "Installing package '$Local:PackageName'...";
        PSColour = 'Green';
    } | Invoke-Write;

    # if ($PackageVersion) {
    #     $Local:PackageArgs['Version'] = $PackageVersion;
    # }

    try {
        & $Script:PackageManagerDetails.Executable $Script:PackageManagerDetails.Commands.Install $Script:PackageManagerDetails.Options.Common $PackageName | Out-Null;
    } catch {
        Invoke-Error "There was an issue while installing $Local:PackageName.";
        Invoke-Error $_.Exception.Message;
    }
}

function Uninstall-ManagedPackage() {

}

function Update-ManagedPackage(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$PackageName
) {
    @{
        PSPrefix = '🔄';
        PSMessage = "Updating package '$Local:PackageName'...";
        PSColour = 'Blue';
    } | Invoke-Write;

    try {
        & $Script:PackageManagerDetails.Executable $Script:PackageManagerDetails.Commands.Update $Script:PackageManagerDetails.Options.Common $PackageName | Out-Null;
    } catch {
        Invoke-Error "There was an issue while updating $Local:PackageName.";
        Invoke-Error $_.Exception.Message;
    }
}

Install-Requirements;
Export-ModuleMember -Function Test-Package, Install-ManagedPackage, Uninstall-Package, Update-Package;
