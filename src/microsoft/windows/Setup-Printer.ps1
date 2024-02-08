#Requires -Version 5.1

Param(
    [Parameter(Mandatory, Position = 0, ParameterSetName = 'Default')]
    [Alias('Name')]
    [String]$PrinterName,

    [Parameter(Mandatory, Position = 1, ParameterSetName = 'Default')]
    [Alias('IP')]
    [String]$PrinterIP,

    [Parameter(Mandatory, ParameterSetName = 'ChocoDriver')]
    [String]$PrinterDriver,

    [Parameter(ParameterSetName = 'ChocoDriver', HelpMessage = "
        The name of the package to install from Chocolatey.
        If not specified, the driver will not be installed.

        If the driver is not installed already and isn't being installed by chocolatey,
        A 5 minute timeout will be used to wait for the driver to be installed asychronously.
    ")]
    [String]$ChocoDriver,

    [Parameter(HelpMessage = "
        If specified, the manufacturer of the printer will be used to determine the driver to install.
        If not specified, the driver will be installed from the Chocolatey package.
    ")]
    [ValidateSet("Ricoh")]
    [String]$Manufacturer,

    [Parameter(HelpMessage = "
        If specified, printer will be added even if the computer cannot contact the printer.
        If not specified, if the computer cannot contact the printer, the script will silently exit.
    ")]
    [Switch]$Force
)

function Install-Driver_Ricoh() {
    [String]$DriverName = 'PCL6 V4 Driver for Universal Print';

    if (Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue) {
        Invoke-Info "Driver $DriverName already installed, skipping...";
        return $DriverName;
    }

    Invoke-WithinEphemeral {
        [String]$Local:URL = 'https://support.ricoh.com/bb/pub_e/dr_ut_e/0001336/0001336407/V42400/r99322L1a.exe';
        [String]$Local:FileName = $Local:URL.Split('/')[-1];
        [String]$Local:ExpandedPath = $Local:FileName.Split('.')[0];

        Invoke-Info "Downloading Ricoh driver from $Local:URL...";
        Invoke-WebRequest -Uri $Local:URL -OutFile $Local:FileName;

        Invoke-Info 'Extracting Ricoh driver...';
        Expand-Archive -Path $Local:FileName -DestinationPath $Local:ExpandedPath;

        Invoke-Info 'Entering Ricoh driver directory...';
        Push-Location -Path $Local:ExpandedPath;

        Invoke-Info 'Finding Ricoh driver inf file...';
        [System.IO.FileInfo]$Local:InfPath = Get-ChildItem -Path .\disk1\*.inf -Recurse | Select-Object -First 1;
        [String]$Local:InfName = $Local:InfPath | Split-Path -Leaf;
        Invoke-Info "Inf file found: $($Local:InfPath.FullName)";
        Invoke-Info "Inf name: $Local:InfName";

        Invoke-Info "Installing Ricoh driver...";
        pnputil.exe /add-driver $Local:InfPath.FullName /install | Out-Null;

        [String]$Local:WindowsDriverPath = 'C:\Windows\System32\DriverStore\FileRepository';
        [System.IO.DirectoryInfo]$Local:DriverPath = Get-ChildItem -Path $Local:WindowsDriverPath -Filter "${Local:InfName}_*" -Recurse | Select-Object -First 1;
        [System.IO.FileInfo]$Local:DriverInfPath = Get-ChildItem -Path $Local:DriverPath.FullName -Filter $Local:InfName -Recurse | Select-Object -First 1;

        Invoke-Info "Adding Ricoh driver to printer drivers...";
        Invoke-Info "Driver name: $DriverName";
        Invoke-Info "Driver path: $($Local:DriverPath.FullName)";
        Invoke-Info "Driver inf path: $($Local:DriverInfPath.FullName)";

        Add-PrinterDriver -Name $DriverName -InfPath $Local:DriverInfPath.FullName;
    }

    return $DriverName;
}

function Install-Driver_Choco(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$DriverName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$ChocolateyPackage
) {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        try {
            Install-ManagedPackage -PackageName $ChocolateyPackage;
        } catch {
            throw "Unable to install package $ChocolateyPackage";
        }
    }
}

function Install-Driver(
    [String]$DriverName,
    [String]$ChocolateyPackage

) {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        if (Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue) {
            Invoke-Info "Driver $DriverName already installed, skipping...";
            return $DriverName;
        } elseif ($ChocolateyPackage) {
            Install-Driver_Choco -DriverName $DriverName -ChocolateyPackage $ChocolateyPackage;
            return $DriverName;
        } elseif ($Manufacturer) {
            switch ($Manufacturer) {
                "Ricoh" { Install-Driver_Ricoh; }
            }
        } else {
            Invoke-Info 'No chocolatey package or manufacturer specified, trying to find driver already installed.';
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
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        if (-not (Get-PrinterPort -Name $PrinterIP -ErrorAction SilentlyContinue)) {
            Invoke-Info "Adding printer port $PrinterIP";
            Add-PrinterPort -Name $PrinterIP -PrinterHostAddress $PrinterIP;
        } else {
            Invoke-Info "Printer port $PrinterIP already exists.";
        }

        if ($Printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue) {
            if ($Printer.DriverName -ne $PrinterDriver) {
                Invoke-Info "Removing existing printer $PrinterName due to mismatching driver $($Printer.DriverName)";
                Remove-Printer -InputObject $Printer;
            }

            if ($Printer.PortName -ne $PrinterIP) {
                Invoke-Info "Removing existing printer $PrinterName due to mismatching port $($Printer.PortName)";
                Remove-Printer -InputObject $Printer;
            }

            if ($Printer.PortName -eq $PrinterIP -and $Printer.DriverName -eq $PrinterDriver) {
                Invoke-Info "Printer $PrinterName already exists";
                return;
            }

            Invoke-Info "Adding printer $PrinterName";

            # TODO :: This can Fail! Need to handle that.
            Add-Printer -Name $PrinterName -DriverName $PrinterDriver -PortName $PrinterIP;
        }
    }
}

Import-Module $PSScriptRoot/../../common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    [String]$Local:PrinterName = $PrinterName.Trim();
    [String]$Local:PrinterIP = $PrinterIP.Trim();
    [String]$Local:PrinterDriver = $PrinterDriver.Trim();
    [String]$Local:ChocoDriver = $ChocoDriver.Trim();

    if (-not $Force -and (-not (Test-Connection -ComputerName $Local:PrinterIP -Count 1 -Quiet))) {
        Invoke-Info "Unable to contact printer $Local:PrinterIP, exiting.";
        return;
    }

    [String]$Local:PrinterDriver = Install-Driver -DriverName $Local:PrinterDriver -ChocolateyPackage $Local:ChocoDriver;
    Install-PrinterImpl -PrinterName $Local:PrinterName -PrinterIP $Local:PrinterIP -PrinterDriver $Local:PrinterDriver;
}
