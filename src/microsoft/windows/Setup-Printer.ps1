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
    [String]$ChocoDriver,

    [Parameter(HelpMessage = "
        If specified, printer will be added even if the computer cannot contact the printer.
        If not specified, if the computer cannot contact the printer, the script will silently exit.
    ")]
    [Switch]$Force
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
        if (-not $ChocolateyPackage) {
            Invoke-Info 'No chocolatey package specified, trying to find driver already installed.';

            [TimeSpan]$Local:WaitTimeout = New-TimeSpan -Minutes 5;
            do {
                Invoke-Info "Waiting for driver $DriverName to be installed; $($Local:WaitTimeout.TotalSeconds) seconds remaining...";
                [DateTime]$Local:StartTime = Get-Date;

                if (Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue) {
                    Invoke-Info "Driver $DriverName found, proceeding...";
                    return;
                }

                [DateTime]$Local:EndTime = Get-Date;
                [TimeSpan]$Local:ProcessingTime -= ($Local:EndTime - $Local:StartTime);
                $Local:WaitTimeout -= $Local:ProcessingTime;

                if ($Local:ProcessingTime.Milliseconds -lt 1000) {
                    Invoke-Verbose "Processing time took less than 1 second, sleeping for the remainder of the second.";
                    Start-Sleep -Milliseconds (1000 - $Local:ProcessingTime.Milliseconds);
                } else {
                    Invoke-Verbose "Wait timeout took longer than 1 second, skipping sleep.";
                }
            } while ($Local:WaitTimeout.TotalSeconds -gt 0)

            throw "Unable to find driver $DriverName";
        } else {
            Install-Package -PackageName $ChocolateyPackage;
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
        if (-not (Get-PrinterPort -Name $PrinterIP -ErrorAction SilentlyContinue)) {
            Invoke-Info "Adding printer port $PrinterIP";
            Add-PrinterPort -Name $PrinterIP -PrinterHostAddress $PrinterIP;
        } else {
            Invoke-Info "Printer port $PrinterIP already exists.";
        }

        if (-not (Get-PrinterPort -Name $PrinterIP -ErrorAction SilentlyContinue)) {
            Invoke-Info "Adding printer port $PrinterIP";
            Add-PrinterPort -Name $PrinterIP -PrinterHostAddress $PrinterIP;
        } else {
            Invoke-Info "Printer port $PrinterIP already exists";
        }

        if (-not (Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue)) {
            Invoke-Info "Adding printer $PrinterName";
            Add-Printer -Name $PrinterName -DriverName $PrinterDriver -PortName $PrinterIP;
        } else {
            Invoke-Info "Printer $PrinterName already exists";
        }
    }
}

Import-Module $PSScriptRoot/../../common/Environment.psm1;
Invoke-RunMain $MyInvocation {
    [String]$Local:PrinterName = $PrinterName.Trim();
    [String]$Local:PrinterIP = $PrinterIP.Trim();
    [String]$Local:PrinterDriver = $PrinterDriver.Trim();
    [String]$Local:ChocoDriver = $ChocoDriver.Trim();

    if (-not $Force -and (-not (Test-Connection -ComputerName $Local:PrinterIP -Count 1 -Quiet))) {
        Invoke-Info "Unable to contact printer $Local:PrinterIP, exiting.";
        return;
    }

    Install-Driver -DriverName $Local:PrinterDriver -ChocolateyPackage $Local:ChocoDriver;
    Install-PrinterImpl -PrinterName $Local:PrinterName -PrinterIP $Local:PrinterIP -PrinterDriver $Local:PrinterDriver;
}
