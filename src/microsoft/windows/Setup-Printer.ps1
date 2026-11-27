#Requires -Version 5.1

Using module ..\..\common\Environment.psm1
Using module ..\..\common\Logging.psm1
Using module ..\..\common\Scope.psm1
Using module ..\..\common\PackageManager.psm1
Using module ..\..\common\Temp.psm1
Using module ..\..\common\Exit.psm1
Using module ..\..\common\Lock.psm1

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
    If specified and one of 'Ricoh', 'HP', 'Konica Minolta', 'Kyocera', or 'Canon', the driver will be installed based on the manufacturer.

.PARAMETER DriverFile
    Path to a pre-downloaded driver archive file.
    If specified, the script uses this file instead of downloading it.
    Only valid for manufacturer-based installations.
    Must point to an existing file on disk.
    For Canon this may be either the vendor self-extracting executable or an already-extracted driver package directory.
    If omitted and no cached copy exists at C:\temp\AMT_SetupPrinter_Driver_Canon.exe, the package is downloaded from Canon's CDN and verified against a pinned SHA256 before use.

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
    [Parameter(Position = 3, ParameterSetName = 'ByManufacturer')]
    [String]$PrinterDriver,

    [Parameter(Position = 3, ParameterSetName = 'ByDriverName')]
    [String]$ChocoDriver,

    [Parameter(Mandatory, Position = 2, ParameterSetName = 'ByManufacturer')]
    [ValidateSet('Ricoh', 'HP', 'Konica Minolta', 'Kyocera', 'Canon')]
    [String]$Manufacturer,

    [Parameter(ParameterSetName = 'ByManufacturer')]
    [ValidateScript({ Test-Path $_ })]
    [String]$DriverFile,

    [Parameter(Position = 4, ParameterSetName = 'ByDriverName')]
    [Parameter(Position = 4, ParameterSetName = 'ByManufacturer')]
    [Switch]$Force
)

function Invoke-DownloadWithProgress {
    param(
        [Parameter(Mandatory)]
        [String]$Uri,
        [Parameter(Mandatory)]
        [String]$OutFile
    )
    $OriginalProgressPreference = $ProgressPreference;
    $ProgressPreference = 'Continue';
    try {
        # -UseBasicParsing: Windows PowerShell 5.1 prompts before parsing web content after the
        # December 2025 hardening (CVE-2025-54100), which hangs unattended runs.
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing;
    } finally {
        $ProgressPreference = $OriginalProgressPreference;
    }
}

function Expand-WinZipSfxArchive {
    param(
        [Parameter(Mandatory)]
        [String]$Path,
        [Parameter(Mandatory)]
        [String]$Destination
    )
    # WinZip self-extractors store central directory offsets relative to the start of the
    # executable, so the embedded ZIP cannot be opened directly. Carve it out and rebase
    # the offsets onto the start of the archive.
    Add-Type -AssemblyName System.IO.Compression.FileSystem;

    # .NET file APIs resolve relative paths against the process working directory, which does
    # not follow Set-Location; anchor both paths to the caller's PowerShell location.
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).ProviderPath $Path));
    }
    if (-not [System.IO.Path]::IsPathRooted($Destination)) {
        $Destination = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).ProviderPath $Destination));
    }

    [Byte[]]$Local:Bytes = [System.IO.File]::ReadAllBytes($Path);

    [Int32]$Local:Eocd = -1;
    [Int32]$Local:Floor = [Math]::Max(0, $Local:Bytes.Length - 65558);
    for ([Int32]$i = $Local:Bytes.Length - 22; $i -ge $Local:Floor; $i--) {
        if ($Local:Bytes[$i] -eq 0x50 -and $Local:Bytes[$i + 1] -eq 0x4B -and $Local:Bytes[$i + 2] -eq 0x05 -and $Local:Bytes[$i + 3] -eq 0x06) {
            $Local:Eocd = $i;
            break;
        }
    }
    if ($Local:Eocd -lt 0) {
        throw "Could not locate an embedded ZIP archive in $Path.";
    }

    [Int32]$Local:CdSize = [BitConverter]::ToUInt32($Local:Bytes, $Local:Eocd + 12);
    [Int32]$Local:CdOffset = [BitConverter]::ToUInt32($Local:Bytes, $Local:Eocd + 16);

    if ($Local:Bytes[$Local:CdOffset] -ne 0x50 -or $Local:Bytes[$Local:CdOffset + 2] -ne 0x01) {
        throw "Unexpected central directory signature in $Path; unsupported self-extractor layout.";
    }

    [Int32]$Local:ArchiveStart = [Int32]::MaxValue;
    for ([Int32]$Local:Entry = $Local:CdOffset; $Local:Entry -lt ($Local:CdOffset + $Local:CdSize);) {
        [Int32]$Local:LocalOffset = [BitConverter]::ToUInt32($Local:Bytes, $Local:Entry + 42);
        if ($Local:LocalOffset -lt $Local:ArchiveStart) { $Local:ArchiveStart = $Local:LocalOffset; }
        $Local:Entry += 46 + [BitConverter]::ToUInt16($Local:Bytes, $Local:Entry + 28) + [BitConverter]::ToUInt16($Local:Bytes, $Local:Entry + 30) + [BitConverter]::ToUInt16($Local:Bytes, $Local:Entry + 32);
    }
    if ($Local:ArchiveStart -lt 0 -or $Local:ArchiveStart -ge $Local:CdOffset) {
        throw "Computed an invalid archive start offset ($($Local:ArchiveStart)).";
    }

    [Int32]$Local:Length = ($Local:Eocd + 22) - $Local:ArchiveStart;
    [Byte[]]$Local:Archive = New-Object Byte[] $Local:Length;
    [Array]::Copy($Local:Bytes, $Local:ArchiveStart, $Local:Archive, 0, $Local:Length);

    [Int32]$Local:RelativeCdOffset = $Local:CdOffset - $Local:ArchiveStart;
    [Array]::Copy([BitConverter]::GetBytes([UInt32]$Local:RelativeCdOffset), 0, $Local:Archive, $Local:Eocd - $Local:ArchiveStart + 16, 4);

    for ([Int32]$Local:Entry = $Local:RelativeCdOffset; $Local:Entry -lt ($Local:RelativeCdOffset + $Local:CdSize);) {
        [Int32]$Local:LocalOffset = [BitConverter]::ToUInt32($Local:Archive, $Local:Entry + 42);
        [Array]::Copy([BitConverter]::GetBytes([UInt32]($Local:LocalOffset - $Local:ArchiveStart)), 0, $Local:Archive, $Local:Entry + 42, 4);
        $Local:Entry += 46 + [BitConverter]::ToUInt16($Local:Archive, $Local:Entry + 28) + [BitConverter]::ToUInt16($Local:Archive, $Local:Entry + 30) + [BitConverter]::ToUInt16($Local:Archive, $Local:Entry + 32);
    }

    [String]$Local:ZipPath = [System.IO.Path]::GetTempFileName();
    try {
        [System.IO.File]::WriteAllBytes($Local:ZipPath, $Local:Archive);
        [System.IO.Compression.ZipFile]::ExtractToDirectory($Local:ZipPath, $Destination);
    } finally {
        Remove-Item -LiteralPath $Local:ZipPath -Force -ErrorAction SilentlyContinue;
    }
}

function Install-Driver_Ricoh {
    param(
        [String]$DriverFile
    )
    [String]$DriverName = 'PCL6 V4 Driver for Universal Print';

    if (Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue) {
        Invoke-Info "Driver $DriverName already installed, skipping...";
        return $DriverName;
    }

    Invoke-WithinEphemeral {
        [String]$Local:URL = 'https://support.ricoh.com/bb/pub_e/dr_ut_e/0001336/0001336407/V42400/r99322L1a.exe';
        [String]$Local:FileName = $Local:URL.Split('/')[-1] -replace '.exe', '.zip';
        [String]$Local:ExpandedPath = $Local:FileName.Split('.')[0];

        if ($DriverFile) {
            Invoke-Info "Using pre-downloaded Ricoh driver file: $DriverFile";
            $Local:FileName = $DriverFile;
        } else {
            Invoke-UnderLock -ResourceId 'Ricoh' -ScriptBlock {
                param([String]$Url, [String]$File)
                Invoke-Info "Downloading Ricoh driver from $Url...";
                Invoke-DownloadWithProgress -Uri $Url -OutFile $File;
            } -ArgumentList $Local:URL, $Local:FileName
        }

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

function Install-Driver_Kyocera {
    param(
        [String]$DriverFile
    )
    [String]$DriverName = 'KX DRIVER for Universal Printing';

    if (Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue) {
        Invoke-Info "Driver $DriverName already installed, skipping...";
        return $DriverName;
    }

    Invoke-WithinEphemeral {
        [String]$URL = 'https://www.kyoceradocumentsolutions.eu/content/dam/download-center-cf/eu/drivers/all/KX_Universal_Printer_Driver_zip.download.zip'
        [String]$FileName = $URL.Split('/')[-1];
        [String]$ExpandedPath = $FileName.Split('.')[0];

        if ($DriverFile) {
            Invoke-Info "Using pre-downloaded Kyocera driver file: $DriverFile";
            $FileName = $DriverFile;
        } else {
            Invoke-UnderLock -ResourceId 'Kyocera' -ScriptBlock {
                param([String]$Url, [String]$File)
                Invoke-Info "Downloading Kyocera driver from $Url...";
                Invoke-DownloadWithProgress -Uri $Url -OutFile $File;
            } -ArgumentList $URL, $FileName
        }
        Invoke-Info 'Extracting Kyocera driver...';
        Expand-Archive -Path $FileName -DestinationPath $ExpandedPath;
        Invoke-Info 'Entering Kyocera driver directory...';
        Push-Location -Path $ExpandedPath;

        Invoke-Info 'Finding Kyocera driver inf file...';
        $Arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture;
        $Folder = switch -Wildcard ($Arch) {
            'X64' { '64bit' }
            'X86' { '32bit' }
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

function Install-Driver_Canon {
    [OutputType([String])]
    param(
        [String]$DriverFile
    )
    # The package ships two self-consistent driver packages that share the same binaries but
    # register different driver names against the same hardware IDs:
    #   Driver\ -> "Canon Generic Plus PCL6"      (DataFile Cnp61M.XPD,    DriverVer 06/23/2026)
    #   etc\    -> "Canon Generic Plus PCL6 V350" (DataFile CNP6350M.XPD,  DriverVer 06/22/2026)
    # Driver\ is the default; the V350 variant exists so a build can sit alongside an existing
    # Generic Plus queue under a version-stamped name.
    [String]$DriverName = 'Canon Generic Plus PCL6';
    [String]$VersionedDriverName = 'Canon Generic Plus PCL6 V350';
    [String]$InfName = 'CNP60MA64.INF';
    # Canon's redirector is the stable entry point; the object URL behind it needs gds/<shard>/
    # which cannot be derived (shard 5 for this build, 404 on every other shard). Returns a 302
    # to the exact package with no cookie, referer or user-agent requirement.
    # Article: https://asia.canon/en/support/0101313501 (Generic Plus PCL6 V3.50, Windows 64bit)
    [String]$DownloadUrl = 'https://pdisp01.c-wss.com/gdl/WWUFORedirectTarget.do?id=MDEwMDAxMzEzNTAx&cmp=ACB&lang=EN';
    [String]$DownloadFile = 'GPlus_PCL6_Driver_V350_W64_00.exe';
    [String]$PackageHash = '2e47a2fbbdb047e71c78a0dfc72756d86eeedceb28d2ff5dcfefdbc053a87bac';

    # Resolve a caller-supplied -DriverFile before Invoke-WithinEphemeral changes location,
    # otherwise a relative path such as .\Canon350 is checked inside the temporary directory.
    [String]$Local:PackagePath = $null;
    if ($DriverFile) {
        try {
            [String]$Local:PackagePath = (Resolve-Path -LiteralPath $DriverFile -ErrorAction Stop).ProviderPath;
        } catch {
            throw "Canon driver package $DriverFile does not exist.";
        }
    }

    # A package directory without a Driver\ tree is the version-stamped etc\ variant; the caller
    # asked for that name by supplying it, so only that name may short-circuit installation.
    [String]$Local:RequestedName = $DriverName;
    [Boolean]$Local:VariantRequested = $false;
    if ($Local:PackagePath -and (Test-Path -LiteralPath $Local:PackagePath -PathType Container) -and
        -not (Test-Path -LiteralPath (Join-Path $Local:PackagePath 'Driver') -PathType Container)) {
        $Local:RequestedName = $VersionedDriverName;
        $Local:VariantRequested = $true;
    }

    if (Get-PrinterDriver -Name $Local:RequestedName -ErrorAction SilentlyContinue) {
        Invoke-Info "Driver $Local:RequestedName already installed, skipping...";
        return $Local:RequestedName;
    }
    if (-not $Local:VariantRequested -and (Get-PrinterDriver -Name $VersionedDriverName -ErrorAction SilentlyContinue)) {
        Invoke-Info "Driver $VersionedDriverName already installed, skipping...";
        return $VersionedDriverName;
    }

    [Hashtable]$Local:Selection = @{ DriverName = $Local:RequestedName; };

    Invoke-WithinEphemeral {
        # Inside this scriptblock $Local: is the scriptblock's own scope; read the enclosing
        # function's values without a scope qualifier.
        [String]$Local:PackagePath = $PackagePath;
        [Boolean]$Local:Downloaded = $false;

        if (-not $Local:PackagePath) {
            Invoke-UnderLock -ResourceId 'Canon' -ScriptBlock {
                param([String]$Url, [String]$File)
                Invoke-Info "Downloading Canon Generic Plus PCL6 driver from $Url...";
                Invoke-DownloadWithProgress -Uri $Url -OutFile $File;
            } -ArgumentList $DownloadUrl, $DownloadFile;
            $Local:PackagePath = $DownloadFile;
            $Local:Downloaded = $true;
        }

        if (-not (Test-Path -LiteralPath $Local:PackagePath)) {
            throw "Canon driver package $Local:PackagePath does not exist.";
        }

        if ($Local:Downloaded) {
            [String]$Local:ActualHash = (Get-FileHash -LiteralPath $Local:PackagePath -Algorithm SHA256).Hash;
            if ($Local:ActualHash -ne $PackageHash) {
                throw "Canon driver package hash mismatch: expected $PackageHash, got $Local:ActualHash. Update the pinned hash deliberately after validating a new release.";
            }
            Invoke-Info "Canon driver package verified (SHA256 $Local:ActualHash).";
        }

        [String]$Local:ExpandedPath = 'Canon';

        if (Test-Path -LiteralPath $Local:PackagePath -PathType Container) {
            Invoke-Info "Using pre-extracted Canon driver package at $Local:PackagePath";
            $Local:ExpandedPath = $Local:PackagePath;
        } else {
            Invoke-Info 'Extracting Canon Generic Plus PCL6 driver package...';
            Expand-WinZipSfxArchive -Path $Local:PackagePath -Destination $Local:ExpandedPath;
        }

        [String]$Local:SelectedDriverName = $RequestedName;
        [String]$Local:InfTree = if ($VariantRequested) { 'etc' } else { 'Driver' };

        [System.IO.FileInfo]$Local:InfPath = Get-ChildItem -LiteralPath (Join-Path $Local:ExpandedPath $Local:InfTree) -Filter $InfName -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1;
        if (-not $Local:InfPath) {
            # The package may only carry the other tree; fall back and take the name that tree registers.
            [String]$Local:FallbackTree = if ($Local:InfTree -eq 'Driver') { 'etc' } else { 'Driver' };
            $Local:InfPath = Get-ChildItem -LiteralPath (Join-Path $Local:ExpandedPath $Local:FallbackTree) -Filter $InfName -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1;
            $Local:SelectedDriverName = if ($Local:FallbackTree -eq 'Driver') { $DriverName } else { $VersionedDriverName };
            if ($Local:InfPath) {
                Invoke-Warn "No $($Local:InfTree)\ package in $($Local:ExpandedPath), falling back to $($Local:FallbackTree)\ ($Local:SelectedDriverName).";
            }
        }
        if (-not $Local:InfPath) {
            throw "Could not find $InfName in the extracted Canon driver package at $Local:ExpandedPath";
        }
        $Selection.DriverName = $Local:SelectedDriverName;
        Invoke-Info "Driver name selected: $Local:SelectedDriverName";

        Invoke-Info "Inf file found: $($Local:InfPath.FullName)";
        Invoke-Info 'Staging Canon driver package...';
        [Object[]]$Local:PnputilOutput = pnputil.exe /add-driver $Local:InfPath.FullName /install 2>&1;
        [Int32]$Local:PnputilExitCode = $LASTEXITCODE;
        [String]$Local:PnputilText = ($Local:PnputilOutput | Out-String).Trim();
        [String]$Local:PublishedInf = [regex]::Match($Local:PnputilText, 'oem\d+\.inf', 'IgnoreCase').Value;

        if ($Local:PnputilExitCode -eq 259 -and $Local:PublishedInf) {
            # 259 is ERROR_NO_MORE_ITEMS: no matching device to install onto. Staging still
            # succeeded, which is all a TCP/IP print queue needs, but only accept it when the
            # package really did land in the driver store.
            Invoke-Info "pnputil reported no matching device (exit 259); package staged as $Local:PublishedInf.";
        } elseif ($Local:PnputilExitCode -ne 0 -and $Local:PnputilExitCode -ne 3010) {
            throw "pnputil failed to stage $InfName (exit code $Local:PnputilExitCode). $Local:PnputilText";
        }

        # Register from the published package that pnputil just created, so the INF path and the
        # driver name come from the same package instead of whichever store directory enumerates first.
        [String]$Local:StoreInfPath = if ($Local:PublishedInf) { Join-Path $env:SystemRoot "INF\$Local:PublishedInf" } else { $null };

        if ($Local:StoreInfPath -and (Test-Path -LiteralPath $Local:StoreInfPath -PathType Leaf)) {
            Invoke-Info "Driver inf in driver store: $Local:StoreInfPath";
            Add-PrinterDriver -Name $Local:SelectedDriverName -InfPath $Local:StoreInfPath -ErrorAction Stop;
        } else {
            Invoke-Warn 'Could not resolve the published driver package path, adding driver by name.';
            Add-PrinterDriver -Name $Local:SelectedDriverName -ErrorAction Stop;
        }
    }

    return $Selection.DriverName;
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
        [Parameter(Mandatory)]
        [ValidateSet('Ricoh', 'HP', 'Konica Minolta', 'Kyocera', 'Canon')]
        [String]$Manufacturer,

        [String]$PrinterDriver,

        [String]$DriverFile
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        $Local:DefaultDriverExtension = if ($Manufacturer -eq 'Canon') { '.exe' } else { '.zip' };
        $Local:DefaultDriverPath = "C:\temp\AMT_SetupPrinter_Driver_$Manufacturer$($Local:DefaultDriverExtension)";

        if ($DriverFile) {
            Invoke-Info "Using specified driver file $DriverFile for manufacturer $Manufacturer";
        } elseif (Test-Path -Path $Local:DefaultDriverPath) {
            Invoke-Info "Driver file found at $Local:DefaultDriverPath, using it for installation.";
            $DriverFile = $Local:DefaultDriverPath;
        } else {
            Invoke-Info "No driver file found at $Local:DefaultDriverPath, downloading driver during installation.";
            $DriverFile = $null;
        }

        $UniversalDriver = switch ($Manufacturer) {
            'Ricoh' { Install-Driver_Ricoh -DriverFile $DriverFile; }
            'HP' { Install-Driver_HP; }
            'Konica Minolta' { Install-Driver_KonciaMinolta; }
            'Kyocera' { Install-Driver_Kyocera -DriverFile $DriverFile; }
            'Canon' { Install-Driver_Canon -DriverFile $DriverFile; }
            default { throw "Unknown manufacturer $Manufacturer"; }
        }

        if ($PrinterDriver) {
            Invoke-Info "Attempting to install driver by name [$PrinterDriver] for manufacturer $Manufacturer...";
            try {
                Add-PrinterDriver -Name $PrinterDriver;
            } catch {
                Invoke-Error "Failed to install driver by name [$PrinterDriver], falling back to universal driver for manufacturer $Manufacturer.";
                Write-Error $_;
                return $UniversalDriver;
            }

            return $PrinterDriver;
        }

        Invoke-Info "No driver name specified, using universal driver [$UniversalDriver] for manufacturer $Manufacturer.";
        return $UniversalDriver;
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

    [String]$Local:InstallPrinterDriver = $PrinterDriver;
    if ($PSCmdlet.ParameterSetName -eq 'ByDriverName') {
        [String]$Local:TrimmedPrinterDriver = $PrinterDriver.Trim();
        [String]$Local:TrimmedChocoDriver = $ChocoDriver.Trim();
        $Local:InstallPrinterDriver = Install-Driver_ByDriverName -DriverName $Local:TrimmedPrinterDriver -ChocolateyPackage $Local:TrimmedChocoDriver;
    } elseif ($PSCmdlet.ParameterSetName -eq 'ByManufacturer') {
        [String]$TrimmedPrinterManufacturer = $Manufacturer.Trim();
        $Local:InstallPrinterDriver = Install-Driver_ByManufacturer -Manufacturer $TrimmedPrinterManufacturer -PrinterDriver $PrinterDriver -DriverFile $DriverFile;
    }

    if (-not $Local:InstallPrinterDriver) {
        Invoke-Error 'Unable to find or install printer driver, exiting.';
        Invoke-FailedExit -ExitCode 1000;
    }

    Install-PrinterImpl -PrinterName $Local:TrimmedPrinterName -PrinterIP $Local:TrimmedPrinterIP -PrinterDriver $Local:InstallPrinterDriver;
}
