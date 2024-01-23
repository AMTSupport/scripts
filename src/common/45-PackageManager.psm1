#Requires -Version 5.1

# TODO :: Add support for other package managers.
$Script:PackageManager = switch ($env:OS) {
    'Windows_NT' {
        $Local:ChocolateyPath = "$($env:SystemDrive)\ProgramData\Chocolatey\bin\choco.exe";

        if (Test-Path -Path $Local:ChocolateyPath) {
            # Ensure Chocolatey is usable.
            Import-Module "$($env:SystemDrive)\ProgramData\Chocolatey\Helpers\chocolateyProfile.psm1" -Force;
            refreshenv | Out-Null;

            $Local:ChocolateyPath;
        } else {
            throw "Chocolatey is not installed on this system.";
        }

        return $Local:ChocolateyPath;
    };
    default {
        throw "Unsupported operating system.";
    };
};
[HashTable]$Script:PackageManagerCommands = switch ($Script:PackageManager) {
    "$($env:SystemDrive)\ProgramData\Chocolatey\bin\choco.exe" {
        @{
            Executable = $Script:PackageManager;
            List       = 'list --local-only';
            Uninstall  = 'uninstall';
            Install    = 'install';
            Update     = 'upgrade';
        };
    };
    default {
        throw "Unsupported package manager.";
    };
};

function Test-Package(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$PackageName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]$PackageVersion
) {
    $Local:Params = @{
        PSPrefix = '🔍';
        PSMessage = "Checking if package '$PackageName' is installed...";
        PSColour = 'Yellow';
    };
    Invoke-Write @Local:Params;

    $Local:PackageArgs = @{
        PackageName = $PackageName;
        Force = $true;
        Confirm = $false;
    };

    if ($PackageVersion) {
        $Local:PackageArgs['Version'] = $PackageVersion;
    }

    & $Script:PackageManager $Script:PackageManagerCommands.List @Local:PackageArgs;
}

function Install-Package(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$PackageName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]$PackageVersion
) {
    $Local:Params = @{
        PSPrefix = '📦';
        PSMessage = "Installing package '$PackageName'...";
        PSColour = 'Green';
    };
    Invoke-Write @Local:Params;

    $Local:PackageArgs = @{
        PackageName = $PackageName;
        Force = $true;
        Confirm = $false;
    };

    if ($PackageVersion) {
        $Local:PackageArgs['Version'] = $PackageVersion;
    }

    & $Script:PackageManager $Script:PackageManagerCommands.Install @Local:PackageArgs;
}

# function Uninstall-Package() {

# }

# function Update-Package() {

# }

# switch ($env:OS) {
#     'Windows_NT' {
#         Import-Module "$($env:SystemDrive)\ProgramData\Chocolatey\Helpers\chocolateyProfile.psm1" -Force
#         refreshenv | Out-Null
#     };
# }

# Export-ModuleMember -Function Install-Package, Test-Package, Uninstall-Package, Update-Package;
