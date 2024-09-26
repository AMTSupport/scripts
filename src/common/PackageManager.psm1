#Requires -Version 5.1

Using module ./Logging.psm1
Using module ./Scope.psm1
Using module ./Exit.psm1
Using module ./Utils.psm1

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
            Commands   = @{
                List      = 'list';
                Uninstall = 'uninstall';
                Install   = 'install';
                Update    = 'upgrade';
            }
            Options    = @{
                Common = @('--confirm', '--limit-output', '--no-progress', '--exact');
                Force  = '--force';
            }
        };
    };
    Unsupported {
        Invoke-Error 'Could not find a supported package manager.';
        $null;
    }
};

[Boolean]$Script:CompletedSetup = $False;
function Local:Install-Requirements {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingInvokeExpression',
        $null,
        Justification = 'Required to install Chocolatey, there is no other way to do this.'
    )]
    [Compiler.Analyser.SuppressAnalyserAttribute(
        'UseOfUndefinedFunction',
        'refreshenv',
        Justification = 'Will be defined by the imported module.'
    )]
    [CmdletBinding()]
    param()

    if ($Script:CompletedSetup) {
        Invoke-Debug 'Setup already completed. Skipping...';
        return;
    }

    if (-not (Test-NetworkConnection)) {
        Invoke-Error 'No network connection detected. Skipping package manager installation.';
        Invoke-FailedExit -ExitCode 9999;
    }

    @{
        PSPrefix  = '📦';
        PSMessage = "Installing requirements for $Script:PackageManager...";
        PSColour  = 'Green';
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

    [Boolean]$Script:CompletedSetup = $True;
}

<#
.SYNOPSIS
    Tests if a package is installed.
.PARAMETER PackageName
    The name of the package to test.
#>
function Test-ManagedPackage(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$PackageName
) {
    begin { Enter-Scope; Install-Requirements; }
    end { Exit-Scope -ReturnValue $Local:Installed; }

    process {
        @{
            PSPrefix  = '🔍';
            PSMessage = "Checking if package '$PackageName' is installed...";
            PSColour  = 'Yellow';
        } | Invoke-Write;

        # if ($PackageVersion) {
        #     $Local:PackageArgs['Version'] = $PackageVersion;
        # }

        [Boolean]$Local:Installed = & $Script:PackageManagerDetails.Executable $Script:PackageManagerDetails.Commands.List $Script:PackageManagerDetails.Options.Common $PackageName;
        Invoke-Verbose "Package '$PackageName' is $(if (-not $Local:Installed) { 'not ' })installed.";
        return $Local:Installed;
    }
}

function Install-ManagedPackage(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$PackageName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]$Sha256,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [Switch]$NoFail

    # [Parameter()]
    # [ValidateNotNullOrEmpty()]
    # [String]$PackageVersion
) {
    begin { Enter-Scope; Install-Requirements; }
    end { Exit-Scope; }

    process {
        @{
            PSPrefix  = '📦';
            PSMessage = "Installing package '$Local:PackageName'...";
            PSColour  = 'Green';
        } | Invoke-Write;

        # if ($PackageVersion) {
        #     $Local:PackageArgs['Version'] = $PackageVersion;
        # }

        [System.Diagnostics.Process]$Local:Process = Start-Process -FilePath $Script:PackageManagerDetails.Executable -ArgumentList (@($Script:PackageManagerDetails.Commands.Install) + $Script:PackageManagerDetails.Options.Common + @($PackageName)) -NoNewWindow -PassThru -Wait;
        if ($Local:Process.ExitCode -ne 0) {
            Invoke-Error "There was an issue while installing $Local:PackageName.";
            Invoke-FailedExit -ExitCode $Local:Process.ExitCode -DontExit:$NoFail;
        }
    }
}

function Uninstall-ManagedPackage() {

}

function Update-ManagedPackage(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$PackageName
) {
    begin { Enter-Scope; Install-Requirements; }
    end { Exit-Scope; }

    process {
        @{
            PSPrefix  = '🔄';
            PSMessage = "Updating package '$Local:PackageName'...";
            PSColour  = 'Blue';
        } | Invoke-Write;

        try {
            & $Script:PackageManagerDetails.Executable $Script:PackageManagerDetails.Commands.Update $Script:PackageManagerDetails.Options.Common $PackageName | Out-Null;

            if ($LASTEXITCODE -ne 0) {
                throw "Error Code: $LASTEXITCODE";
            }
        } catch {
            Invoke-Error "There was an issue while updating $Local:PackageName.";
            Invoke-Error $_.Exception.Message;
        }
    }
}

Export-ModuleMember -Function Test-ManagedPackage, Install-ManagedPackage, Uninstall-Package, Update-ManagedPackage;
