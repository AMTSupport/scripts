#Requires -RunAsAdministrator

Using module ..\..\common\Scope.psm1
Using module ..\..\common\Logging.psm1
Using module ..\..\common\Registry.psm1

$TradeMarkUnicode = [char]0x2122;
$RegisteredTradeMarkUnicode = [char]0x00AE;

function Get-SupportedProcessor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String]$Brand
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        $Brand = $Brand -replace 'GenuineIntel', 'Intel' `
            -replace 'AuthenticAMD', 'AMD';

        $ProcessorsUrl = "https://learn.microsoft.com/en-us/windows-hardware/design/minimum/supported/windows-11-supported-$Brand-processors";
        $ProcessorsRequest = Invoke-WebRequest -Uri $ProcessorsUrl -UseBasicParsing;
        $ParsedHtml = New-Object -Com 'HTMLFile';
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            # Fucking peice of shit.
            $CorrectEncoding = [System.Text.Encoding]::UTF8.GetString($ProcessorsRequest.RawContentStream.ToArray());
            $ParsedHtml.IHTMLDocument2_write($CorrectEncoding)
        } else {
            $ParsedHtml.write([ref]$ProcessorsRequest.Content);
        }
        $RawProcessors = (($ParsedHtml.getElementsByTagName('table') | Select-Object -First 1 | Select-Object -ExpandProperty innerText)) -split '\r\n';

        if ($Brand -eq 'Intel') {
            $SupportedProcessors = $RawProcessors | ForEach-Object {
                $_ -replace $RegisteredTradeMarkUnicode, '(R),' `
                    -replace $TradeMarkUnicode, '(TM),' `
                    -replace 'Processor', 'Processor,'; # Single outlier that needs to be split
            };
        } elseif ($Brand -eq 'AMD') {
            $SupportedProcessors = $RawProcessors | ForEach-Object {
                $Split = $_.Substring(3) -split ',';

                # Ordering is important here, as we want to split on the most specific first
                $BrandModelSplitPoints = @(
                    "Ryzen$TradeMarkUnicode Threadripper$TradeMarkUnicode PRO"
                    "Ryzen$TradeMarkUnicode Embedded"
                    'Ryzen Embedded R2000 Series'
                    "Ryzen$TradeMarkUnicode \d [A-z]+"
                    "Ryzen$TradeMarkUnicode \d"
                    "Ryzen$TradeMarkUnicode"
                    "EPYC$TradeMarkUnicode"
                    "Athlon$TradeMarkUnicode"
                    'AMD'
                );

                $BrandModel = $Split -split "($($BrandModelSplitPoints -join '|'))";
                "AMD,$($BrandModel[1]),$($BrandModel[2])" -replace $TradeMarkUnicode, '';
            };
        } elseif ($Brand -eq 'Qualcomm') {
            $SupportedProcessors = $RawProcessors | ForEach-Object {
                $_ -replace $RegisteredTradeMarkUnicode, ',' `
                    -replace $TradeMarkUnicode, ',';
            };
        } else {
            Invoke-Error "Unsupported processor brand: $Brand";
            return $null;
        }

        $SupportedProcessors = $SupportedProcessors -replace '\[\d+\]', '';

        $Headers = @("Manufactuer", "Brand", "Model");
        $SupportedProcessors = $SupportedProcessors | Select-Object -Skip 1 | ConvertFrom-Csv -Header $Headers -Delimiter ',';

        return $SupportedProcessors;
    }
}

function Test-CanUpgrade {
    [CmdletBinding()]
    [OutputType([Boolean])]
    param(
        [Switch]$AlwaysShowResults
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        if ($env:OS -ne 'Windows_NT') {
            Invoke-Error 'This script is only supported on Windows.';
            return $False;
        }

        [String]$Private:OSCaption = (Get-CimInstance -Query 'select caption from win32_operatingsystem' | Select-Object -Property Caption).Caption;
        if ($Private:OSCaption -match 'Windows 11') {
            Invoke-Info 'Already running Windows 11, no need to upgrade.';
            if (-not $AlwaysShowResults) {
                return $False;
            }
        }

        $Processor = Get-CimInstance -ClassName Win32_Processor;
        $SupportedProcessors = Get-SupportedProcessor -Brand $Processor.Manufacturer;
        $CPUIsSupported = $null -ne ($SupportedProcessors | Where-Object {
            "$($Processor.Name)".Contains("$($_.Manufactuer) $($_.Brand) $($_.Model)");
        });

        $Tpm = Get-Tpm;
        $Result = @{
            'TPM Present' = $Tpm.TpmPresent;
            'TPM Version 2.0' = $Tpm.ManufacturerVersionFull20 -notlike '*not supported*';
            'Processor Compatible' = $CPUIsSupported;
            '64 Bit OS' = [System.Environment]::Is64BitOperatingSystem;
        };

        if ($Result.Values -contains $False -or $Result["64 Bit OS"] -eq $False) {
            Invoke-Error 'Your system does not meet the minimum requirements to upgrade to Windows 11, see the details below:';
            $Result.GetEnumerator() | ForEach-Object {
                Invoke-Error "$($_.Key): $($_.Value)";
            }
            return $False;
        }

        if ($AlwaysShowResults) {
            Invoke-Info 'Your system meets the minimum requirements to upgrade to Windows 11, see the details below:';
            $Result.GetEnumerator() | ForEach-Object {
                Invoke-Info "$($_.Key): $($_.Value)";
            }
        }

        $Private:RequiredSpace = 25GB;
        $Private:AvailableSpace = (Get-Volume -DriveLetter C).SizeRemaining;
        if ($Private:AvailableSpace -lt $Private:RequiredSpace) {
            Invoke-Error "Not enough space to upgrade to Windows 11, you need at least 25GB of free space on your system drive.";
            return $False;
        }

        return $True;
    }
}

function Write-SetupError([Bool]$MaybeSuccess) {
    $RegPath = 'HKLM:\SYSTEM\Setup\setupdiag\results';
    $Success = Get-RegistryKey $RegPath 'OperationCompletedSuccessfully';
    if ($False -and $MaybeSuccess -and $Success -eq 'True') {
        Invoke-Info 'Windows 11 upgrade completed successfully';
    } else {
        $FailureData = Get-RegistryKey $RegPath 'FailureData';
        $FailureDetails = Get-RegistryKey $RegPath 'FailureDetails';

        Invoke-Error "Windows 11 upgrade failed, see the details below:";
        Invoke-Error "Failure Data: $FailureData";
        Invoke-Error "Failure Details: $FailureDetails";

        # $ErrorCode = $FailureDetails | Select-String -Pattern 'ErrorCode = (0x\d+),' | ForEach-Object { $_.Matches.Groups[1].Value };
        # $ScanResultFile = "$env:SystemDrive\`$WINDOWS.~BT\Sources\Panther\ScanResult.xml";
        $ScanResultFile = "C:\Users\JamesDraycott\AppData\Local\Temp\ScanResult.xml";
        if (Test-Path $ScanResultFile) {
            Invoke-Verbose 'Checking for blocking drivers...';

            $PnpDevices = Get-PnpDevice -PresentOnly;
            $PnpDeviceInfs = @{};
            $PnpDevices | ForEach-Object {
                $InfPath = $_ | Get-PnpDeviceProperty -KeyName 'DEVPKEY_Device_DriverInfPath';
                $PnpDeviceInfs[$_.InstanceId] = $InfPath.Data;
            }

            $DriverPackages = (Select-Xml -Path $ScanResultFile -XPath '/*').Node.DriverPackages.DriverPackage;
            $DriverPackages | ForEach-Object {
                $Driver = $_;
                if ($Driver.BlockMigration -eq 'True') {
                    $DriverName = $Driver.Inf;
                    $DriverDetails = Get-WindowsDriver -Online -Driver $DriverName;
                    $InUseByDevices = $PnpDevices | Where-Object {
                        $PnpDeviceInfs[$_.InstanceId] -eq $DriverName;
                    }

                    Invoke-Error @"
Driver: $DriverName is blocking the upgrade to Windows 11, see the details below:
    In Use By Devices: $($InUseByDevices | Select-Object -ExpandProperty FriendlyName -Join ', ')
    Driver Details: $DriverDetails
"@
                }
            }
        }
    }
}

function Update-ToWin11 {
    [CmdletBinding()]
    param()

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        $Private:Dir = "$env:TEMP\Windows11Upgrade";
        if (-not (Test-Path $Private:Dir)) {
            New-Item -ItemType Directory -Path $Private:Dir;
        }

        $Private:OutputFile = "$Private:Dir\Windows11InstallationAssistant.exe";
        Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?linkid=2171764' -OutFile $Private:OutputFile -UseBasicParsing;
        Unblock-File -Path $Private:OutputFile;

        Invoke-Info 'Starting Windows 11 upgrade, this will take a while with no progress bar...';
        try {
            $UnsupportedFeatures = @('Printing-PrintToPDFServices-Features', 'Printing-XPSServices-Features');
            $UnsupportedFeatures | ForEach-Object {
                $Status = Get-WindowsOptionalFeature -FeatureName $_ -Online;
                if ($Status.State -eq 'Enabled' -or $Status.State -eq 'EnablePending') {
                    Invoke-Info "Disabling feature: $_";
                    Disable-WindowsOptionalFeature -FeatureName $_ -Online;
                }
            }

            # TODO - Maybe use the processes resource monitor to determine if its downloading, copying or what?
            # Dont auto reboot
            Start-Process -FilePath $Private:OutputFile -ArgumentList "/QuietInstall /SkipEULA /auto upgrade /UninstallUponUpgrade /copylogs $Private:Dir" -Wait;

            # send ui message after complete
            Write-SetupError $True;
        } catch {
            Invoke-Error "There was an error upgrading to Windows 11, please check the logs for more information inside $Private:Dir";
            Write-SetupError $False;
            $PSCmdlet.ThrowTerminatingError($_);
        }
    }
}

Export-ModuleMember -Function 'Update-ToWin11', 'Test-CanUpgrade', 'Get-SupportedProcessor', 'Write-SetupError';
