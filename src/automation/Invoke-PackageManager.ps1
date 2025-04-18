Using module ..\common\Environment.psm1
Using module ..\common\Exit.psm1
Using module ..\common\Ensure.psm1
Using module ..\common\Logging.psm1
Using module ..\common\PackageManager.psm1

[CmdletBinding(SupportsShouldProcess)]
Param(
    [Parameter(ValueFromRemainingArguments)]
    [String[]]$AdditionalPackages
)

<#
.SYNOPSIS
    A HashTable of the default packages along with a ScriptBlock to retry the installation of the package if it fails.
#>
$Script:DefaultPackages = @{
    # Google Chrome fails to install because old versions cannot be grabbed and the sha256 is out of date.
    # The script gets the latest version and sha256 from the website and then installs it with the correct version and sha256.
    googlechrome = @{
        Retry = {
            [String]$Local:ActualSha256 = (Get-FileHash -InputStream ([System.Net.WebClient]::new().OpenRead('https://dl.google.com/tag/s/dl/chrome/install/googlechromestandaloneenterprise64.msi'))).Hash;
            Install-ManagedPackage -PackageName 'googlechrome' -Sha256 $Local:ActualSha256;
        };
    };
    adobereader = {};
    displaylink = {};
}

Invoke-RunMain $PSCmdlet {
    Invoke-EnsureAdministrator;

    [System.Management.Automation.ErrorRecord[]]$Local:Errors = @();
    [HashTable]$Local:Packages = $Script:DefaultPackages;
    if ($AdditionalPackages) {
        $AdditionalPackages | ForEach-Object { $Local:Packages.Add($_, @{}); };
    }

    $Script:DefaultPackages.GetEnumerator() | ForEach-Object {
        Invoke-Debug "Processing package '$($_.Key)'...";
        [String]$Local:PackageName = $_.Key;
        $Local:Package = $_.Value;

        [Boolean]$Local:NoUpdate = $False;
        if (-not (Test-ManagedPackage -PackageName $Local:PackageName)) {
            try {
                $ErrorActionPreference = 'Stop';

                Install-ManagedPackage -PackageName $Local:PackageName;
                [Boolean]$Local:NoUpdate = $True;
            } catch {
                if ($Local:Package.Retry) {
                    Invoke-Info "Retrying installation of package '$Local:PackageName'...";
                    try {
                        $ErrorActionPreference = 'Stop';

                        & $Local:Package.Retry;
                        [Boolean]$Local:NoUpdate = $True;
                    } catch {
                        $Local:Errors += $_;
                    }
                } else {
                    $Local:Errors += $_;
                }
            }
        }

        if (-not $Local:NoUpdate) {
            Invoke-Info "Updating package '$Local:PackageName'...";
            try {
                $ErrorActionPreference = 'Stop';

                Update-ManagedPackage -PackageName $Local:PackageName;
            } catch {
                $Local:Errors += $_;
            }
        }
    };

    if ($Local:Errors) {
        $Local:Errors | ForEach-Object { $_.Exception.Message; };
        Invoke-FailedExit -ExitCode 1001 -ErrorRecord $Local:Errors[0];
    }
};
