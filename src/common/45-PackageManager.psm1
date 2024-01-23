#Requires -Version 5.1

# TODO :: Add support for other package managers.
[String]$Script:PackageManager = switch ($env:OS) {
    'Windows_NT' { "choco" };
    default {
        throw "Unsupported operating system.";
    };
};
[HashTable]$Script:PackageManager = switch ($Script:PackageManager) {
    "choco" {
        [String]$Local:ChocolateyPath = "$($env:SystemDrive)\ProgramData\Chocolatey\bin\choco.exe";
        if (Test-Path -Path $Local:ChocolateyPath) {
            # Ensure Chocolatey is usable.
            Import-Module "$($env:SystemDrive)\ProgramData\Chocolatey\Helpers\chocolateyProfile.psm1" -Force;
            refreshenv | Out-Null;
        } else {
            throw 'Chocolatey is not installed on this system.';
        }

        @{
            Executable = $Local:ChocolateyPath;
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
    default {
        throw "Unsupported package manager.";
    };
};

function Test-Package(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$PackageName

    # [Parameter()]
    # [ValidateNotNullOrEmpty()]
    # [String]$PackageVersion
) {
    $Local:Params = @{
        PSPrefix = '🔍';
        PSMessage = "Checking if package '$PackageName' is installed...";
        PSColour = 'Yellow';
    };
    Invoke-Write @Local:Params;

    # if ($PackageVersion) {
    #     $Local:PackageArgs['Version'] = $PackageVersion;
    # }

    # TODO :: Actually get the return value.
    & $Script:PackageManager.Executable $Script:PackageManager.Commands.List $Script:PackageManager.Options.Common $PackageName;
}

function Install-ManagedPackage(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$PackageName

    # [Parameter()]
    # [ValidateNotNullOrEmpty()]
    # [String]$PackageVersion
) {
    @{
        PSPrefix = '📦';
        PSMessage = "Installing package '$PackageName'...";
        PSColour = 'Green';
    } | Invoke-Write;

    # if ($PackageVersion) {
    #     $Local:PackageArgs['Version'] = $PackageVersion;
    # }

    # TODO :: Ensure success.
    & $Script:PackageManager.Executable $Script:PackageManager.Commands.Install $Script:PackageManager.Options.Common $PackageName;
}

function Uninstall-Package() {

}

function Update-Package() {

}

Export-ModuleMember -Function Test-Package, Install-ManagedPackage, Uninstall-Package, Update-Package;
