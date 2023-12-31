#Requires -Version 5.1
#Requires -RunAsAdministrator

# Windows Setup screen raw inputs
# enter,down,enter,enter,tab,tab,tab,enter,tab,tab,tab,tab,tab,tab,enter,tab,tab,tab,tab,enter,localadmin,enter,enter,enter,enter,tab,tab,tab,tab,tab,enter,tab,tab,tab,tab,enter

# After windows setup
# windows,powershell,right,down,enter,left,enter,Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process,enter,a,enter,D:\win_setup.ps1,enter

[CmdletBinding(SupportsShouldProcess)]
Param (
    [Parameter()]
    [ValidateSet("Configure", "Cleanup", "Install", "Update", "Finish")]
    [String]$Phase = "Configure",

    [Parameter(DontShow)]
    [ValidateLength(32, 32)]

    [Parameter(DontShow)]
    [ValidateNotNullOrEmpty()]
    [String]$Endpoint = "system-monitor.com",

    [Parameter(DontShow)]
    [ValidateNotNullOrEmpty()]
    [String]$NetworkName = "Guests",

    [Parameter(DontShow)]
    [ValidateNotNullOrEmpty()]

    [Parameter(DontShow)]
    [ValidateNotNullOrEmpty()]
    [String]$TaskName = "SetupScheduledTask",

    [Parameter(DontShow)]
    [ValidateNotNullOrEmpty()]
    [Int]$RecursionLevel = 0
)

#region - Error Codes

$Script:NULL_ARGUMENT = 1000;
$Script:FAILED_TO_LOG = 1001;
$Script:FAILED_TO_CONNECT = 1002;
$Script:ALREADY_RUNNING = 1003;
$Script:FAILED_EXPECTED_VALUE = 1004;
$Script:FAILED_SETUP_ENVIRONMENT = 1005;

$Script:AGENT_FAILED_DOWNLOAD = 1011;
$Script:AGENT_FAILED_EXPAND = 1012;
$Script:AGENT_FAILED_FIND = 1013;
$Script:AGENT_FAILED_INSTALL = 1014;

$Script:FAILED_REGISTRY = 1021;

#endregion - Error Codes

#region - Utility Functions

function Get-SoapResponse(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Uri
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:ParsedResponse; }

    process {
        [String]$Local:ContentType = "text/xml;charset=`"utf-8`"";
        [String]$Local:Method = "GET"

        $Local:Response = Invoke-RestMethod -Uri $Uri -ContentType $Local:ContentType -Method $Local:Method
        [System.Xml.XmlElement]$Local:ParsedResponse = $Local:Response.result

        $Local:ParsedResponse
    }
}

function Get-BaseUrl(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Service
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        "https://${Endpoint}/api/?apikey=$ApiKey&service=$Service"
    }
}

function Get-FormattedName2Id(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [Object[]]$InputArr,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ScriptBlock]$IdExpr
) {
    begin { Enter-Scope -Invocation $MyInvocation; }

    process {
        $InputArr | Select-Object -Property @{Name = 'Name'; Expression = { $_.name.'#cdata-section' } }, @{Name = 'Id'; Expression = $IdExpr }
    }

    end { Exit-Scope -Invocation $MyInvocation; }
}

#endregion - Utility Functions

#region - Environment Setup

# Setup Network if there is no existing connection.
function Invoke-EnsureNetworkSetup {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        [Boolean]$Local:HasNetwork = (Get-NetConnectionProfile `
            | Where-Object {
                $Local:HasIPv4 = $_.IPv4Connectivity -eq "Internet";
                $Local:HasIPv6 = $_.IPv6Connectivity -eq "Internet";

                $Local:HasIPv4 -or $Local:HasIPv6
            } | Measure-Object | Select-Object -ExpandProperty Count) -gt 0;

        if ($Local:HasNetwork) {
            Invoke-Info 'Network is already setup, skipping network setup...';
            return
        }

        Invoke-Info "No Wi-Fi connection found, creating profile..."

        [String]$Local:ProfileFile = "$env:TEMP\SetupWireless-profile.xml";
        If ($Local:ProfileFile | Test-Path) {
            Invoke-Info 'Profile file exists, removing it...';
            Remove-Item -Path $Local:ProfileFile -Force;
        }

        $Local:SSIDHEX = ($NetworkName.ToCharArray() | foreach-object { '{0:X}' -f ([int]$_) }) -join ''
        $Local:XmlContent = "<?xml version=""1.0""?>
<WLANProfile xmlns=""http://www.microsoft.com/networking/WLAN/profile/v1"">
    <name>$NetworkName</name>
    <SSIDConfig>
        <SSID>
            <hex>$Local:SSIDHEX</hex>
            <name>$NetworkName</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$NetworkPassword</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
";

        if ($WhatIfPreference) {
            Invoke-Info "Dry run enabled, skipping profile creation..."
            Invoke-Info "Would have created profile file $Local:ProfileFile with contents:"
            Invoke-Info $Local:XmlContent
        } else {
            Invoke-Info "Creating profile file $Local:ProfileFile...";
            $Local:XmlContent > ($Local:ProfileFile);

            netsh wlan add profile filename="$($Local:ProfileFile)" | Out-Null
            netsh wlan show profiles $NetworkName key=clear | Out-Null
            netsh wlan connect name=$NetworkName | Out-Null
        }

        Invoke-Info "Waiting for network connection..."
        $Local:RetryCount = 0;
        while (-not (Test-Connection -Destination google.com -Count 1 -Quiet)) {
            If ($Local:RetryCount -ge 60) {
                Invoke-Error "Failed to connect to $NetworkName after 10 retries";
                Invoke-FailedExit -ExitCode $Script:FAILED_TO_CONNECT;
            }

            Start-Sleep -Seconds 1
            $Local:RetryCount += 1
        }

        Invoke-Info "Connected to $NetworkName."
    }
}

# If the script isn't located in the temp folder, copy it there and run it from there.
function Invoke-EnsureLocalScript {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        [String]$Local:ScriptPath = $MyInvocation.PSScriptRoot;
        [String]$Local:TempPath = (Get-Item $env:TEMP).FullName;

        $Local:ScriptPath | Assert-NotNull -Message "Script path was null, this really shouldn't happen.";
        $Local:TempPath | Assert-NotNull -Message "Temp path was null, this really shouldn't happen.";

        if ($Local:ScriptPath -ne $Local:TempPath) {
            Invoke-Info "Copying script to temp folder...";
            [String]$Local:Into = "$Local:TempPath\$($MyInvocation.PSCommandPath | Split-Path -Leaf)";

            try {
                Copy-Item -Path $MyInvocation.PSCommandPath -Destination $Local:Into -Force;
            } catch {
                Invoke-Error "Failed to copy script to temp folder";
                Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:FAILED_SETUP_ENVIRONMENT;
            }

            Add-QueuedTask -QueuePhase $Phase -ScriptPath $Local:Into;
            Invoke-Info 'Exiting original process due to script being copied to temp folder...';
            Invoke-QuickExit;
        }
    }
}

# Get all required user input for the rest of the script to run automatically.
function Invoke-EnsureSetupInfo {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        [String]$Local:File = "$($env:TEMP)\InstallInfo.json";

        If (Test-Path $Local:File) {
            Invoke-Info "Install Info exists, checking validity...";

            try {
                [PSCustomObject]$Local:InstallInfo = Get-Content -Path $Local:File -Raw | ConvertFrom-Json;
                $Local:InstallInfo | Assert-NotNull -Message "Install info was null";

                [String]$Local:DeviceName = $Local:InstallInfo.DeviceName;
                $Local:DeviceName | Assert-NotNull -Message "Device name was null";

                [String]$Local:ClientId = $Local:InstallInfo.ClientId;
                $Local:ClientId | Assert-NotNull -Message "Client id was null";

                [String]$Local:SiteId = $Local:InstallInfo.SiteId;
                $Local:SiteId | Assert-NotNull -Message "Site id was null";

                [String]$Local:Path = $Local:InstallInfo.Path;
                $Local:Path | Assert-NotNull -Message "Path was null";


                return $Local:InstallInfo;
            } catch {
                Invoke-Warn 'There was an issue with the install info, deleting the file for recreation...';
                Remove-Item -Path $Local:File -Force;
            }
        }

        Invoke-Info 'No install info found, creating new install info...';

        #region - Get Client Selection
        $Local:Clients = (Get-SoapResponse -Uri (Get-BaseUrl "list_clients")).items.client;
        $Local:Clients | Assert-NotNull -Message "Failed to get clients from N-Able";

        $Local:FormattedClients = Get-FormattedName2Id -InputArr $Clients -IdExpr { $_.clientid }
        $Local:FormattedClients | Assert-NotNull -Message "Failed to format clients";

        $Local:SelectedClient = Get-PopupSelection -InputAttrs $Local:FormattedClients -ItemName "client";
        #endregion - Get Client Selection

        #region - Get Site Selection
        $Local:Sites = (Get-SoapResponse -Uri "$(Get-BaseUrl "list_sites")&clientid=$($SelectedClient.Id)").items.site;
        $Local:Sites | Assert-NotNull -Message "Failed to get sites from N-Able";

        $Local:FormattedSites = Get-FormattedName2Id -InputArr $Sites -IdExpr { $_.siteid };
        $Local:FormattedSites | Assert-NotNull -Message "Failed to format sites";

        $Local:SelectedSite = Get-PopupSelection -InputAttrs $Local:FormattedSites -ItemName "site";
        #endregion - Get Site Selection

        # TODO - Show a list of devices for the selected client so the user can confirm they're using the correct naming convention
        [String]$Local:DeviceName = Get-UserInput -Title "Device Name" -Question "Enter a name for this device"

        [PSCustomObject]$Local:InstallInfo = @{
            "DeviceName" = $Local:DeviceName
            "ClientId"   = $Local:SelectedClient.Id
            "SiteId"     = $Local:SelectedSite.Id
            "Path"       = $Local:File
        };

        Invoke-Info "Saving install info to $Local:File...";
        try {
            $Local:InstallInfo | ConvertTo-Json | Out-File -FilePath $File -Force;
        } catch {
            Invoke-Error "There was an issue saving the install info to $Local:File";
            Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:FAILED_SETUP_ENVIRONMENT;
        }

        return $Local:InstallInfo;
    }
}

# Make sure all required modules have been installed.
function Invoke-EnsureModulesInstalled {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        Import-DownloadableModule -Name PSWindowsUpdate;
    }
}

#endregion - Environment Setup

#region - Queue Functions

function Remove-QueuedTask {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        [CimInstance]$Local:Task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue;
        if (-not $Local:Task) {
            Invoke-Verbose -Message "Scheduled task [$TaskName] does not exist, skipping removal...";
            return;
        }

        Invoke-Verbose -Message "Removing scheduled task [$TaskName]...";
        $Local:Task | Unregister-ScheduledTask -ErrorAction Stop -Confirm:$false;
    }
}

function Add-QueuedTask(
    [Parameter(Mandatory)]
    [ValidateSet("Configure", "Cleanup", "Install", "Update", "Finish")]
    [String]$QueuePhase,

    [Parameter(HelpMessage="The path of the script to run when the task is triggered.")]
    [ValidateNotNullOrEmpty()]
    [String]$ScriptPath = $MyInvocation.PSCommandPath,

    [switch]$OnlyOnRebootRequired = $false
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        [Boolean]$Local:RequiresReboot = (Get-RebootFlag).Required();
        if ($OnlyOnRebootRequired -and (-not $Local:RequiresReboot)) {
            Invoke-Info "The device does not require a reboot before the $QueuePhase phase can be started, skipping queueing...";
            return;
        }

        # Schedule the task before possibly rebooting.
        $Local:Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -WakeToRun;

        [String]$Local:RunningUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name;
        $Local:RunningUser | Assert-NotNull -Message "Running user was null, this really shouldn't happen.";
        $Local:Principal = New-ScheduledTaskPrincipal -UserId $Local:RunningUser -RunLevel Highest;

        $Local:Trigger = switch ($Local:RequiresReboot) {
            $true { New-ScheduledTaskTrigger -AtLogOn -User $Local:RunningUser; }
            $false { New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5); }
        };

        [Int]$Local:RecursionLevel = if ($Phase -eq $QueuePhase) { $RecursionLevel + 1 } else { 0 };
        [String[]]$Local:AdditionalArgs = @("-Phase $QueuePhase", "-RecursionLevel $Local:RecursionLevel");
        if ($WhatIfPreference) {
            $Local:AdditionalArgs += "-WhatIf";
        }
        if ($VerbosePreference -ne "SilentlyContinue") {
            $Local:AdditionalArgs += "-Verbose";
        }

        $Local:Action = New-ScheduledTaskAction `
            -Execute 'powershell.exe' `
            -Argument "-ExecutionPolicy Bypass -NoExit -File `"$ScriptPath`" $($Local:AdditionalArgs -join ' ')";

        $Local:Task = New-ScheduledTask `
            -Action $Local:Action `
            -Principal $Local:Principal `
            -Settings $Local:Settings `
            -Trigger $Local:Trigger;

        Register-ScheduledTask -TaskName $TaskName -InputObject $Task -Force -ErrorAction Stop | Out-Null;

        if ($Local:RequiresReboot) {
            Invoke-Info "The device requires a reboot before the $QueuePhase phase can be started, rebooting in 15 seconds...";
            Invoke-Info 'Press any key to cancel the reboot...';
            $Host.UI.RawUI.FlushInputBuffer();
            $Local:Countdown = 150;
            while ($Local:Countdown -gt 0) {
                if ([Console]::KeyAvailable) {
                    Invoke-Info 'Key was pressed, canceling reboot.';
                    break;
                }

                Write-Progress `
                    -Activity "Writing Reboot Countdown" `
                    -Status "Rebooting in $([Math]::Floor($Local:Countdown / 10)) seconds..." `
                    -PercentComplete (($Local:Countdown / 150) * 100);

                $Local:Countdown -= 1;
                Start-Sleep -Milliseconds 100;
            }

            if ($Local:Countdown -eq 0) {
                Invoke-Info "Rebooting now...";

                (Get-RunningFlag).Remove();
                (Get-RebootFlag).Remove();
                Restart-Computer -Force;
            }
        }
    }
}

#endregion - Queue Functions

#region - Phase Functions

# Configure items like device name from the setup the user provided.
function Invoke-PhaseConfigure([Parameter(Mandatory)][ValidateNotNullOrEmpty()][PSCustomObject]$InstallInfo) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:NextPhase; }

    process {
        $InstallInfo | Assert-NotNull -Message "Install info was null";

        #region - Device Name
        [String]$Local:DeviceName = $InstallInfo.DeviceName;
        $Local:DeviceName | Assert-NotNull -Message "Device name was null";

        [String]$Local:ExistingName = $env:COMPUTERNAME;
        $Local:ExistingName | Assert-NotNull -Message "Existing name was null"; # TODO :: Alternative method of getting existing name if $env:COMPUTERNAME is null

        if ($Local:ExistingName -eq $Local:DeviceName) {
            Invoke-Info "Device name is already set to $Local:DeviceName.";
        } else {
            Invoke-Info "Device name is not set to $Local:DeviceName, setting it now...";
            Rename-Computer -NewName $Local:DeviceName;
            (Get-RebootFlag).Set($null);
        }
        #endregion - Device Name

        #region - Auto-Login
        [String]$Local:RegKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon";
        try {
            $ErrorActionPreference = "Stop";

            Set-ItemProperty -Path $Local:RegKey -Name "AutoAdminLogon" -Value 1 | Out-Null;
            Set-ItemProperty -Path $Local:RegKey -Name "DefaultUserName" -Value "localadmin" | Out-Null;
            Set-ItemProperty -Path $Local:RegKey -Name "DefaultPassword" -Value "" | Out-Null;

            Invoke-Info 'Auto-login registry keys set.';
        } catch {
            Invoke-Error "Failed to set auto-login registry keys";
            Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:FAILED_REGISTRY;
        }
        #endregion - Auto-Login

        [String]$Local:NextPhase = "Cleanup";
        return $Local:NextPhase;
    }
}

function Invoke-PhaseCleanup {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:NextPhase; }

    process {
        function Invoke-Progress {
            Param(
                [Parameter(Mandatory)][ValidateNotNull()]
                [ScriptBlock]$GetItems,

                [Parameter(Mandatory)][ValidateNotNull()]
                [ScriptBlock]$ProcessItem,

                [ScriptBlock]$FailedProcessItem
            )

            [String]$Local:ProgressActivity = $MyInvocation.MyCommand.Name;

            Write-Progress -Activity $Local:ProgressActivity -CurrentOperation "Getting items..." -PercentComplete 0;
            [Object[]]$Local:InputItems = $GetItems.InvokeReturnAsIs();
            Write-Progress -Activity $Local:ProgressActivity -PercentComplete 10;

            if ($null -eq $Local:InputItems -or $Local:InputItems.Count -eq 0) {
                Write-Progress -Activity $Local:ProgressActivity -Status "No items found." -PercentComplete 100 -Completed;
                return;
            } else {
                Write-Progress -Activity $Local:ProgressActivity -Status "Processing $($Local:InputItems.Count) items...";
            }

            [System.Collections.IList]$Local:FailedItems = New-Object System.Collections.Generic.List[System.Object];
            [Int]$Local:PercentPerItem = 90 / $Local:InputItems.Count;
            [Int]$Local:PercentComplete = 0;
            foreach ($Local:Item in $Local:InputItems) {
                Write-Progress -Activity $Local:ProgressActivity -CurrentOperation "Processing item [$Local:Item]..." -PercentComplete $Local:PercentComplete;

                try {
                    $ErrorActionPreference = "Stop";
                    $ProcessItem.InvokeReturnAsIs($Local:Item);
                } catch {
                    Invoke-Warn "Failed to process item [$Local:Item]";
                    try {
                        $ErrorActionPreference = "Stop";

                        if ($null -eq $FailedProcessItem) {
                            $Local:FailedItems.Add($Local:Item);
                        } else { $FailedProcessItem.InvokeReturnAsIs($Local:Item); }
                    } catch {
                        Invoke-Warn "Failed to process item [$Local:Item] in failed process item block";
                    }
                }

                $Local:PercentComplete += $Local:PercentPerItem;
            }
            Write-Progress -Activity $Local:ProgressActivity -PercentComplete 100 -Completed;

            if ($Local:FailedItems.Count -gt 0) {
                Invoke-Warn "Failed to process $($Local:FailedItems.Count) items";
                Invoke-Warn "Failed items: `n`t$($Local:FailedItems -join "`n`t")";
            }
        }
        function Stop-Services_HP {
            begin { Enter-Scope -Invocation $MyInvocation; }
            end { Exit-Scope -Invocation $MyInvocation; }

            process {
                [String[]]$Local:Services = @("HotKeyServiceUWP", "HPAppHelperCap", "HP Comm Recover", "HPDiagsCap", "HotKeyServiceUWP", "LanWlanWwanSwitchingServiceUWP", "HPNetworkCap", "HPSysInfoCap", "HP TechPulse Core");

                Invoke-Info "Disabling $($Services.Value.Count) services...";
                Invoke-Progress -GetItems { $Local:Services } -ProcessItem {
                    Param($ServiceName)

                    try {
                        $ErrorActionPreference = 'Stop';

                        $Local:Instance = Get-Service -Name $ServiceName;
                    } catch {
                        Invoke-Warn "Skipped service $ServiceName as it isn't installed.";
                    }

                    if ($Local:Instance) {
                        Invoke-Info "Stopping service $Local:Instance...";
                        try {
                            $ErrorActionPreference = 'Stop';

                            $Local:Instance | Stop-Service -Force -Confirm:$false;
                            Invoke-Info "Stopped service $Local:Instance";
                        } catch {
                            Invoke-Info -Message "Failed to stop $Local:Instance";
                        }

                        Invoke-Info "Disabling service $ServiceName...";
                        try {
                            $ErrorActionPreference = 'Stop';

                            $Local:Instance | Set-Service -StartupType Disabled -Force -Confirm:$false;
                            Invoke-Info "Disabled service $ServiceName";
                        } catch {
                            Invoke-Warn "Failed to disable $ServiceName";
                        }
                    }
                };
            }
        }
        function Remove-Programs_HP {
            begin { Enter-Scope -Invocation $MyInvocation; }
            end { Exit-Scope -Invocation $MyInvocation; }

            process {
                [String[]]$Programs = @(
                    'HPJumpStarts'
                    'HPPCHardwareDiagnosticsWindows'
                    'HPPowerManager'
                    'HPPrivacySettings'
                    'HPSupportAssistant'
                    'HPSureShieldAI'
                    'HPSystemInformation'
                    'HPQuickDrop'
                    'HPWorkWell'
                    'myHP'
                    'HPDesktopSupportUtilities'
                    'HPQuickTouch'
                    'HPEasyClean'
                    'HPPCHardwareDiagnosticsWindows'
                    'HPProgrammableKey'
                );

                [String[]]$UninstallablePrograms = @(
                    "HP Device Access Manager"
                    "HP Client Security Manager"
                    "HP Connection Optimizer"
                    "HP Documentation"
                    "HP MAC Address Manager"
                    "HP Notifications"
                    "HP System Info HSA Service"
                    "HP Security Update Service"
                    "HP System Default Settings"
                    "HP Sure Click"
                    "HP Sure Click Security Browser"
                    "HP Sure Run"
                    "HP Sure Run Module"
                    "HP Sure Recover"
                    "HP Sure Sense"
                    "HP Sure Sense Installer"
                    "HP Wolf Security"
                    "HP Wolf Security - Console"
                    "HP Wolf Security Application Support for Sure Sense"
                    "HP Wolf Security Application Support for Windows"
                );

                Invoke-Progress -GetItems { Get-Package | Where-Object { $UninstallablePrograms -contains $_.Name -or $Programs -contains $_.Name } } -ProcessItem {
                    Param($Program)

                    $Local:Product = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq $Program.Name };
                    if (-not $Local:Product) {
                        throw "Can't find MSI Package for program [$($Program.Name)]";
                    } else {
                        msiexec /x $Local:Product.IdentifyingNumber /quiet /noreboot | Out-Null;
                        Invoke-Info "Sucessfully removed program [$($Local:Product.Name)]";
                    }
                };

                # Fallback attempt 1 to remove HP Wolf Security using msiexec
                Try {
                    MsiExec /x "{0E2E04B0-9EDD-11EB-B38C-10604B96B11E}" /qn /norestart
                    Invoke-Info -Object "Fallback to MSI uninistall for HP Wolf Security initiated"
                } Catch {
                    Invoke-Warn -Object "Failed to uninstall HP Wolf Security using MSI - Error message: $($_.Exception.Message)"
                }

                # Fallback attempt 2 to remove HP Wolf Security using msiexec
                Try {
                    MsiExec /x "{4DA839F0-72CF-11EC-B247-3863BB3CB5A8}" /qn /norestart
                    Invoke-Info -Object "Fallback to MSI uninistall for HP Wolf 2 Security initiated"
                } Catch {
                    Invoke-Warn -Object  "Failed to uninstall HP Wolf Security 2 using MSI - Error message: $($_.Exception.Message)"
                }
            }
        }
        function Remove-ProvisionedPackages_HP {
            begin { Enter-Scope -Invocation $MyInvocation; }
            end { Exit-Scope -Invocation $MyInvocation; }

            process {
                [String]$HPIdentifier = "AD2F1837";

                Invoke-Progress -GetItems { Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -match "^$HPIdentifier" } } -ProcessItem {
                    Param($Package)

                    Remove-AppxProvisionedPackage -PackageName $Package.PackageName -Online -AllUsers;
                    Invoke-Info "Sucessfully removed provisioned package [$($Package.DisplayName)]";
                }
            }
        }
        function Remove-AppxPackages_HP {
            begin { Enter-Scope -Invocation $MyInvocation; }
            end { Exit-Scope -Invocation $MyInvocation; }

            process {
                [String]$HPIdentifier = "AD2F1837";

                Invoke-Progress -GetItems { $Packages = Get-AppxPackage -AllUsers | Where-Object { $_.Name -match "^$HPIdentifier" }; $Packages } -ProcessItem {
                    Param($Package)

                    Remove-AppxPackage -Package $Package.PackageFullName -AllUsers;
                    Invoke-Info "Sucessfully removed appx-package [$($Package.Name)]";
                };
            }
        }
        function Remove-Drivers_HP {
            begin { Enter-Scope -Invocation $MyInvocation; }
            end { Exit-Scope -Invocation $MyInvocation; }

            process {
                # Uninstalling the drivers disables and (on reboot) removes the installed services.
                # At this stage the only 'HP Inc.' driver we want to keep is HPSFU, used for firmware servicing.
                Invoke-Progress -GetItems { Get-WindowsDriver -Online | Where-Object { $_.ProviderName -eq 'HP Inc.' -and $_.OriginalFileName -notlike '*\hpsfuservice.inf' } } -ProcessItem {
                    Param($Driver)

                    pnputil /delete-driver $Driver /uninstall /force;
                    Invoke-Info "Removed driver: $($_.OriginalFileName.toString())";
                };

                # Once the drivers are gone lets disable installation of 'drivers' for these HP 'devices' (typically automatic via Windows Update)
                # SWC\HPA000C = HP Device Health Service
                # SWC\HPIC000C = HP Application Enabling Services
                # SWC\HPTPSH000C = HP Services Scan
                # ACPI\HPIC000C = HP Application Driver
                $RegistryPath = 'HKLM:\Software\Policies\Microsoft\Windows\DeviceInstall\Restrictions\DenyDeviceIDs'

                If (! (Test-Path $RegistryPath)) { New-Item -Path $RegistryPath -Force | Out-Null }

                New-ItemProperty -Path $RegistryPath -Name '1' -Value 'SWC\HPA000C' -PropertyType STRING
                New-ItemProperty -Path $RegistryPath -Name '2' -Value 'SWC\HPIC000C' -PropertyType STRING
                New-ItemProperty -Path $RegistryPath -Name '3' -Value 'SWC\HPTPSH000C' -PropertyType STRING
                New-ItemProperty -Path $RegistryPath -Name '4' -Value 'ACPI\HPIC000C' -PropertyType STRING

                $RegistryPath = 'HKLM:\Software\Policies\Microsoft\Windows\DeviceInstall\Restrictions'

                New-ItemProperty -Path $RegistryPath -Name 'DenyDeviceIDs' -Value '1' -PropertyType DWORD
                New-ItemProperty -Path $RegistryPath -Name 'DenyDeviceIDsRetroactive' -Value '1' -PropertyType DWORD
            }
        }

        Stop-Services_HP;
        Remove-ProvisionedPackages_HP;
        Remove-AppxPackages_HP;
        Remove-Programs_HP;

        # Queue next phase as self if still needed for Wolf uninstall.
        [String]$Local:NextPhase = "Install";
        return $Local:NextPhase;
    }
}

# Install the agent and any other required software.
function Invoke-PhaseInstall([Parameter(Mandatory)][ValidateNotNullOrEmpty()][PSCustomObject]$InstallInfo) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:NextPhase; }

    process {
        [String]$Local:AgentServiceName = "Advanced Monitoring Agent";
        [String]$Local:NextPhase = "Update";

        # Check if the agent is already installed and running.
        if (Get-Service -Name $Local:AgentServiceName -ErrorAction SilentlyContinue) {
            Invoke-Info "Agent is already installed, skipping installation...";
            return $Local:NextPhase;
        }

        Invoke-WithinEphemeral {
            [String]$Local:ClientId = $InstallInfo.ClientId;
            [String]$Local:SiteId = $InstallInfo.SiteId;
            [String]$Local:Uri = "https://system-monitor.com/api/?apikey=${ApiKey}&service=get_site_installation_package&endcustomerid=${ClientId}&siteid=${SiteId}&os=windows&type=remote_worker";

            Invoke-Info "Downloading agent from [$Local:Uri]";
            try {
                $ErrorActionPreference = "Stop";
                Invoke-WebRequest -Uri $Local:Uri -OutFile 'agent.zip' -UseBasicParsing;
            } catch {
                Invoke-Error "Failed to download agent from [$Local:Uri]";
                Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:AGENT_FAILED_DOWNLOAD;
            }

            Invoke-Info "Expanding archive...";
            try {
                $ErrorActionPreference = "Stop";

                Expand-Archive -Path 'agent.zip' -DestinationPath .;
            } catch {
                Invoke-Error "Failed to expand archive";
                Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:AGENT_FAILED_EXPAND;
            }

            Invoke-Info "Finding agent executable...";
            try {
                $ErrorActionPreference = 'Stop';

                [String]$Local:OutputExe = Get-ChildItem -Path . -Filter '*.exe' -File;
                $Local:OutputExe | Assert-NotNull -Message "Failed to find agent executable";
            } catch {
                Invoke-Info "Failed to find agent executable";
                Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:AGENT_FAILED_FIND;
            }

            Invoke-Info "Installing agent from [$Local:OutputExe]...";
            try {
                $ErrorActionPreference = 'Stop';

                [System.Diagnostics.Process]$Local:Installer = Start-Process -FilePath $Local:OutputExe -Wait -PassThru;
                $Local:Installer.ExitCode | Assert-Equals -Expected 0 -Message "Agent installer failed with exit code [$($Local:Installer.ExitCode)]";

                (Get-RebootFlag).Set($null);
            } catch {
                Invoke-Error "Failed to install agent from [$Local:OutputExe]";
                Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:AGENT_FAILED_INSTALL;
            }

            while ($true) {
                $Local:AgentStatus = Get-Sevice -Name $Local:AgentServiceName -ErrorAction SilentlyContinue;
                if ($Local:AgentStatus -and $Local:AgentStatus.Status -eq 'Running') {
                    Invoke-Info "The agent has been installed and running, current status is [$Local:AgentStatus]...";
                    break;
                }

                Start-Sleep -Milliseconds 100;
            }
        }

        Invoke-Info 'Unable to determine when the agent is fully installed, sleeping for 5 minutes...';
        $Local:Countdown = 3000;
        while ($Local:Countdown -gt 0) {
            Write-Progress `
                -Activity "Agent Installation" `
                -Status "Waiting for $([Math]::Floor($Local:Countdown / 10)) seconds..." `
                -PercentComplete (($Local:Countdown / 150) * 100)
                -Complete ($Local:Countdown -eq 1);

            $Local:Countdown -= 1;
            Start-Sleep -Milliseconds 100;
        }

        # TODO - Query if sentinel is configured, if so wait for sentinel and the agent to be running services, then restart the computer

        return $Local:NextPhase;
    }
}

function Invoke-PhaseUpdate {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:NextPhase; }

    process {
        [String]$Local:NextPhase = if ($RecursionLevel -ge 2) { "Finish" } else { "Update" };

        Get-WindowsUpdate -Install -AcceptAll -AutoReboot:$false -IgnoreReboot -IgnoreUserInput -Confirm:$false;
        (Get-RebootFlag).Set($null);

        return $Local:NextPhase;
    }
}

function Invoke-PhaseFinish {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:NextPhase; }

    process {
        [String]$Local:NextPhase = $null;

        #region - Remove localadmin Auto-Login
        $Local:RegKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon";
        try {
            $ErrorActionPreference = "Stop";

            Remove-ItemProperty -Path $Local:RegKey -Name "AutoAdminLogon" -Force -ErrorAction Stop;
            Remove-ItemProperty -Path $Local:RegKey -Name "DefaultUserName" -Force -ErrorAction Stop;
            Remove-ItemProperty -Path $Local:RegKey -Name "DefaultPassword" -Force -ErrorAction Stop;
        } catch {
            Invoke-Error "Failed to remove auto-login registry keys";
            Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:FAILED_REGISTRY;
        }
        #endregion - Remove localadmin Auto-Login

        return $Local:NextPhase;
    }
}

#endregion - Phase Functions

Import-Module $PSScriptRoot/../../common/Environment.psm1;
Invoke-RunMain $MyInvocation {
    try {
        Trap {
            Invoke-FailedExit -ErrorRecord $_ -ExitCode 9999;
        }

        Register-ExitHandler -Name 'Running Flag Removal' -ExitHandler {
            (Get-RunningFlag).Remove();
        };

        Register-ExitHandler -Name 'Queued Task Removal' -OnlyFailure -ExitHandler {
            Remove-QueuedTask;
        };

        # Ensure only one process is running at a time.
        If ((Get-RunningFlag).IsRunning()) {
            Invoke-Error "The script is already running in another session, exiting...";
            Exit $Script:ALREADY_RUNNING;
        } else {
            (Get-RunningFlag).Set($null);
            Remove-QueuedTask;
        }

        try {
            Invoke-EnsureLocalScript;
            Invoke-EnsureNetworkSetup;
            Invoke-EnsureModulesInstalled;
            $Local:InstallInfo = Invoke-EnsureSetupInfo;

            # Queue this phase to run again if a restart is required by one of the environment setups.
            Add-QueuedTask -QueuePhase $Phase -OnlyOnRebootRequired;
        } catch {
            Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:FAILED_SETUP_ENVIRONMENT;
        }

        Invoke-QuickExit;

        [String]$Local:NextPhase = $null;
        switch ($Phase) {
            'configure' { [String]$Local:NextPhase = Invoke-PhaseConfigure -InstallInfo $Local:InstallInfo; }
            'cleanup' { [String]$Local:NextPhase = Invoke-PhaseCleanup; }
            'install' { [String]$Local:NextPhase = Invoke-PhaseInstall -InstallInfo $Local:InstallInfo; }
            'update' { [String]$Local:NextPhase = Invoke-PhaseUpdate; }
            'finish' { [String]$Local:NextPhase = Invoke-PhaseFinish; }
        }

        # Should only happen when we are done and there is nothing else to queue.
        if (-not $Local:NextPhase) {
            Invoke-Info "No next phase was returned, exiting...";
            Invoke-QuickExit;
        }

        Invoke-Info "Queueing next phase [$Local:NextPhase]...";
        Add-QueuedTask -QueuePhase $Local:NextPhase;
        Invoke-QuickExit;
    } finally {
        (Get-RunningFlag).Remove();
    }
}
