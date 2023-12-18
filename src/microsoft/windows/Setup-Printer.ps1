#Requires -Version 5.1

Param(
    [Parameter(Mandatory)]
    [String]$PrinterName,

    [Parameter(Mandatory)]
    [String]$PrinterIP,

    [Parameter(Mandatory)]
    [String]$PrinterDriver,

    [Parameter(HelpMessage = "
        The name of the package to install from Chocolatey.
        If not specified, the driver will not be installed.

        If the driver is not installed already and isn't being installed by chocolatey,
        A 5 minute timeout will be used to wait for the driver to be installed asychronously.
    ")]
    [String]$ChocoDriver
)

function Install-Driver(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$DriverName,

    [String]$ChocolateyPackage

) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        Trap {
            Write-Host -ForegroundColor Red -Object "Encountered an error while trying to install/find printer driver $DriverName.";
            throw $_;
        }

        if (-not $ChocolateyPackage) {
            Write-Host -ForegroundColor Cyan -Object 'No chocolatey package specified, trying to find driver already installed.';

            [TimeSpan]$Local:WaitTimeout = New-TimeSpan -Minutes 5;
            do {
                Write-Verbose -Message "Waiting for driver $DriverName to be installed; $($Local:WaitTimeout.TotalSeconds) seconds remaining...";
                [DateTime]$Local:StartTime = Get-Date;

                if (Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue) {
                    Write-Host -ForegroundColor Cyan -Object "Driver $DriverName found, proceeding...";
                    return;
                }

                [DateTime]$Local:EndTime = Get-Date;
                [TimeSpan]$Local:ProcessingTime -= ($Local:EndTime - $Local:StartTime);
                $Local:WaitTimeout -= $Local:ProcessingTime;

                if ($Local:ProcessingTime.Milliseconds -lt 1000) {
                    Write-Verbose -Message "Processing time took less than 1 second, sleeping for the remainder of the second.";
                    Start-Sleep -Milliseconds (1000 - $Local:ProcessingTime.Milliseconds);
                } else {
                    Write-Verbose -Message "Wait timeout took longer than 1 second, skipping sleep.";
                }
            } while ($Local:WaitTimeout.TotalSeconds -gt 0)

            throw "Unable to find driver $DriverName";
        } else {
            Import-Module "$($env:SystemDrive)\ProgramData\Chocolatey\Helpers\chocolateyProfile.psm1" -Force
            refreshenv | Out-Null

            choco install -y -e --limit-output $ChocolateyPackage;
        }
    }
}

function Install-PrinterImpl(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$PrinterName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$PrinterIP,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$PrinterDriver
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        Trap {
            Write-Host -ForegroundColor Red -Object "Encountered an error while trying to install printer $PrinterName.";
            throw $_;
        }

        if (-not (Get-PrinterPort -Name $PrinterIP -ErrorAction SilentlyContinue)) {
            Write-Host -ForegroundColor Cyan -Object "Adding printer port $PrinterIP";
            Add-PrinterPort -Name $PrinterIP -PrinterHostAddress $PrinterIP;
        } else {
            Write-Host -ForegroundColor Cyan -Object "Printer port $PrinterIP already exists.";
        }

        if (-not (Get-PrinterPort -Name $PrinterIP -ErrorAction SilentlyContinue)) {
            Write-Host -ForegroundColor Cyan -Object "Adding printer port $PrinterIP";
            Add-PrinterPort -Name $PrinterIP -PrinterHostAddress $PrinterIP;
        } else {
            Write-Host -ForegroundColor Cyan -Object "Printer port $PrinterIP already exists";
        }

        if (-not (Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue)) {
            Write-Host -ForegroundColor Cyan -Object "Adding printer $PrinterName";
            Add-Printer -Name $PrinterName -DriverName $PrinterDriver -PortName $PrinterIP;
        } else {
            Write-Host -ForegroundColor Cyan -Object "Printer $PrinterName already exists";
        }
    }
}

Import-Module $PSScriptRoot/../../common/Environment.psm1;
Invoke-RunMain $MyInvocation {
    Install-Driver -DriverName $PrinterDriver -ChocolateyPackage $ChocoDriver;
    Install-PrinterImpl -PrinterName $PrinterName -PrinterIP $PrinterIP -PrinterDriver $PrinterDriver;
}
