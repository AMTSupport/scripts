#Requires -Version 5.1

Using module ..\..\common\Environment.psm1
Using module ..\..\common\Logging.psm1
Using module ..\..\common\Scope.psm1
Using module ..\..\common\PackageManager.psm1
Using module ..\..\common\Temp.psm1
Using module ..\..\common\Exit.psm1

<#
.PARAMETER PrinterName
    The name of the printer.

.PARAMETER PrinterIP
    The IP address of the printer.

.PARAMETER PrinterDriver
    The name of the printer driver as it appears in the list of installed drivers.

.PARAMETER ChocoDriver
    The name of the package to install from Chocolatey.
    If not specified, the driver will not be installed.

    If the driver is not installed already and isn't being installed by chocolatey,
    A 5 minute timeout will be used to wait for the driver to be installed asychronously.

.PARAMETER Manufacturer
    If specified and one of 'Ricoh', 'HP', 'Konica Minolta', or 'Kyocera', the driver will be installed based on the manufacturer.

.PARAMETER Force
    If specified, printer will be added even if the computer cannot contact the printer.
    If not specified, if the computer cannot contact the printer, the script will silently exit.
#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByDriverName')]
    [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByManufacturer')]
    [Alias('Name')]
    [String]$PrinterName,

    [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByDriverName')]
    [Parameter(Mandatory, Position = 1, ParameterSetName = 'ByManufacturer')]
    [Alias('IP')]
    [String]$PrinterIP,

    [Parameter(Mandatory, Position = 2, ParameterSetName = 'ByDriverName')]
    [String]$PrinterDriver,

    [Parameter(Position = 3, ParameterSetName = 'ByDriverName')]
    [String]$ChocoDriver,

    [Parameter(Mandatory, Position = 2, ParameterSetName = 'ByManufacturer')]
    [ValidateSet('Ricoh', 'HP', 'Konica Minolta', 'Kyocera')]
    [String]$Manufacturer,

    [Parameter(Position = 4, ParameterSetName = 'ByDriverName')]
    [Parameter(Position = 3, ParameterSetName = 'ByManufacturer')]
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
        [String]$Local:FileName = $Local:URL.Split('/')[-1] -replace '.exe', '.zip';
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

        Invoke-Info 'Installing Ricoh driver...';
        pnputil.exe /add-driver $Local:InfPath.FullName /install | Out-Null;

        [String]$Local:WindowsDriverPath = 'C:\Windows\System32\DriverStore\FileRepository';
        [System.IO.DirectoryInfo]$Local:DriverPath = Get-ChildItem -Path $Local:WindowsDriverPath -Filter "${Local:InfName}_*" -Recurse | Select-Object -First 1;
        [System.IO.FileInfo]$Local:DriverInfPath = Get-ChildItem -Path $Local:DriverPath.FullName -Filter $Local:InfName -Recurse | Select-Object -First 1;

        Invoke-Info 'Adding Ricoh driver to printer drivers...';
        Invoke-Info "Driver name: $DriverName";
        Invoke-Info "Driver path: $($Local:DriverPath.FullName)";
        Invoke-Info "Driver inf path: $($Local:DriverInfPath.FullName)";

        Add-PrinterDriver -Name $DriverName -InfPath $Local:DriverInfPath.FullName;
    }

    return $DriverName;
}

function Install-Driver_Kyocera() {
    [String]$DriverName = 'KX DRIVER for Universal Printing';

    if (Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue) {
        Invoke-Info "Driver $DriverName already installed, skipping...";
        return $DriverName;
    }

    Invoke-WithinEphemeral {
        [String]$URL = 'https://www.kyoceradocumentsolutions.us/content/download-center-americas/us/drivers/drivers/KX_DRIVER_zip.download.zip';
        [String]$FileName = $URL.Split('/')[-1];
        [String]$ExpandedPath = $FileName.Split('.')[0];

        Invoke-Info "Downloading Kyocera driver from $URL...";
        Invoke-WebRequest -Uri $URL -OutFile $FileName;
        Invoke-Info 'Extracting Kyocera driver...';
        Expand-Archive -Path $FileName -DestinationPath $ExpandedPath;
        Invoke-Info 'Entering Kyocera driver directory...';
        Push-Location -Path $ExpandedPath;

        Invoke-Info 'Finding Kyocera driver inf file...';
        $Arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture;
        $Folder = switch -Wildcard ($Arch) {
            'X64' { '32bit' }
            'X86' { '64bit' }
            'Arm*' { 'arm64' }
            default { throw "Unsupported architecture: $Arch" }
        }

        [System.IO.FileInfo]$InfPath = Get-ChildItem -Path ".\**\${Folder}\*.inf" -Recurse | Select-Object -First 1;
        [String]$InfName = $InfPath | Split-Path -Leaf;

        Invoke-Info "Inf file found: $($InfPath.FullName)";
        Invoke-Info "Inf name: $InfName";
        Invoke-Info 'Installing Kyocera driver...';
        pnputil.exe /add-driver $InfPath.FullName /install | Out-Null;

        try {
            Add-PrinterDriver -Name $DriverName;
        } catch {
            Invoke-Error "Failed to add Kyocera driver $DriverName. Trying to install from inf file." -Throw;
        }
    }


    return $DriverName;
}

function Install-Driver_HP() {
    [String]$DriverName = 'HP Universal Printing PCL 6';

    if (Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue) {
        Invoke-Info "Driver $DriverName already installed, skipping...";
        return $DriverName;
    }

    Invoke-Info 'Installing HP Universal Print Driver...';
    Install-ManagedPackage -PackageName 'hp-universal-print-driver-pcl';

    return $DriverName;
}

function Install-Driver_KonciaMinolta() {
    [String]$DriverName = 'Konica Minolta Universal PCL';

    if (Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue) {
        Invoke-Info "Driver $DriverName already installed, skipping...";
        return $DriverName;
    }

    Invoke-Info 'Installing Konica Minolta Universal PCL driver...';
    Install-ManagedPackage -PackageName 'kmupd';

    return $DriverName;
}

function Install-Driver_ByDriverName(
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
            Install-ManagedPackage -PackageName $ChocolateyPackage;
            return $DriverName;
        }

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
                Invoke-Verbose 'Processing time took less than 1 second, sleeping for the remainder of the second.';
                Start-Sleep -Milliseconds (1000 - $Local:ProcessingTime.Milliseconds);
            } else {
                Invoke-Verbose 'Wait timeout took longer than 1 second, skipping sleep.';
            }
        } while ($Local:WaitTimeout.TotalSeconds -gt 0)

        throw "Unable to find driver $DriverName";
    }
}

function Install-Driver_ByManufacturer {
    [OutputType([String])]
    param(
        [String]$DriverName
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        switch ($Manufacturer) {
            'Ricoh' { return Install-Driver_Ricoh; }
            'HP' { return Install-Driver_HP; }
            'Konica Minolta' { return Install-Driver_KonciaMinolta; }
            'Kyocera' { return Install-Driver_Kyocera; }
            default { throw "Unknown manufacturer $Manufacturer"; }
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
                Invoke-Info "Printer $PrinterName already exists with matching driver and port, skipping...";
                return;
            }
        }

        Invoke-Info "Adding printer $PrinterName";
        # TODO :: This can Fail! Need to handle that.
        try {
            Add-Printer -Name $PrinterName -DriverName $PrinterDriver -PortName $PrinterIP;
        } catch {
            Invoke-Error "There was an error adding the printer $PrinterName";
            Invoke-FailedExit -ExitCode 1001 -ErrorRecord $_;
        }
    }
}

Invoke-RunMain $PSCmdlet {
    [String]$Local:TrimmedPrinterName = $PrinterName.Trim();
    [String]$Local:TrimmedPrinterIP = $PrinterIP.Trim();

    if (-not $Force -and (-not (Test-Connection -ComputerName $Local:TrimmedPrinterIP -Count 1 -Quiet))) {
        Invoke-Warn "Unable to contact printer $Local:TrimmedPrinterIP, exiting.";
        return;
    }

    [String]$Local:PrinterDriver = $null;
    if ($PSCmdlet.ParameterSetName -eq 'ByDriverName') {
        [String]$Local:TrimmedPrinterDriver = $PrinterDriver.Trim();
        [String]$Local:TrimmedChocoDriver = $ChocoDriver.Trim();
        $Local:PrinterDriver = Install-Driver_ByDriverName -DriverName $Local:TrimmedPrinterDriver -ChocolateyPackage $Local:TrimmedChocoDriver;
    } elseif ($PSCmdlet.ParameterSetName -eq 'ByManufacturer') {
        $Local:PrinterDriver = Install-Driver_ByManufacturer -Manufacturer $Local:TrimmedPrinterManufacturer;
    }

    if (-not $Local:PrinterDriver) {
        Invoke-Error 'Unable to find or install printer driver, exiting.';
        Invoke-FailedExit -ExitCode 1000;
    }

    Install-PrinterImpl -PrinterName $Local:TrimmedPrinterName -PrinterIP $Local:TrimmedPrinterIP -PrinterDriver $Local:PrinterDriver;
}
