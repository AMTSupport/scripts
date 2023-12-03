#Requires -Version 5.1
#Requires -RunAsAdministrator

# Windows Setup screen raw inputs
# enter,down,enter,enter,tab,tab,tab,enter,tab,tab,tab,tab,tab,tab,enter,tab,tab,tab,tab,enter,localadmin,enter,enter,enter,enter,tab,tab,tab,tab,tab,enter,tab,tab,tab,tab,enter

# After windows setup
# windows,powershell,right,down,enter,left,enter,Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process,enter,a,enter,D:\win_setup.ps1,enter

Param (
    [Parameter()]
    [switch]$DryRun,

    [Parameter]
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

#endregion - Error Codes

#region - Utility Functions

function Get-SoapResponse($Uri) {
    begin { Enter-Scope $MyInvocation }

    process {
        $ContentType = "text/xml;charset=`"utf-8`""
        $Method = "GET"
        $Response = Invoke-RestMethod -Uri $Uri -ContentType $ContentType -Method $Method
        [System.Xml.XmlElement]$ParsedResponse = $Response.result

        $ParsedResponse
    }

    end { Exit-Scope $MyInvocation }
}

function Get-BaseUrl([String]$Service) {
    begin { Enter-Scope $MyInvocation }

    process {
        "https://${Endpoint}/api/?apikey=$ApiKey&service=$Service"
    }

    end { Exit-Scope $MyInvocation }
}

function Get-FormattedName2Id([Object[]]$InputArr, [ScriptBlock]$NameExpr = { $_.name."#cdata-section" }, [ScriptBlock]$IdExpr) {
    begin { Enter-Scope $MyInvocation }

    process {
        $InputArr | Select-Object -Property @{Name = "Name"; Expression = $NameExpr }, @{Name = "Id"; Expression = $IdExpr }
    }

    end { Exit-Scope $MyInvocation }
}

function Get-TempFolder([Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$Sub, [switch]$ForceEmpty) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:TempFolder; }

    process {
        [String]$Local:TempFolder = "$($env:TEMP)\$Sub";

        if ($ForceEmpty) {
            Write-Host "Emptying temporary folder $Local:TempFolder..."
            Remove-Item -Path $Local:TempFolder -Force -Recurse
            New-Item -ItemType Directory -Path $Local:TempFolder
        }
        elseif (-not (Test-Path $Local:TempFolder)) {
            Write-Host "Creating temporary folder $Local:TempFolder..."
            New-Item -ItemType Directory -Path $Local:TempFolder
        }
        else {
            Write-Host "Temporary folder $Local:TempFolder already exists."
        }

        $Local:TempFolder
    }
}

function Import-DownloadableModule([String]$Name) {
    begin { Enter-Scope $MyInvocation }

    process {
        $Module = Get-Module -ListAvailable | Where-Object { $_.Name -eq $Name }
        if ($null -eq $Module) {
            Write-Host "Downloading module $Name..."
            Install-PackageProvider -Name NuGet -Confirm:$false
            Install-Module -Name $Name -Scope CurrentUser -Confirm:$false -Force
            $Module = Get-Module -ListAvailable | Where-Object { $_.Name -eq $Name }
        }

        Import-Module $Module
    }

    end { Exit-Scope $MyInvocation }
}

#endregion - Utility Functions

#region - Environment Setup

# Setup Network if there is no existing connection.
function Invoke-EnsureNetworkSetup {
    begin { Enter-Scope $MyInvocation }
    end { Exit-Scope $MyInvocation }

    process {
        [Boolean]$Local:HasNetwork = (Get-NetConnectionProfile `
            | Where-Object {
                $Local:HasIPv4 = $_.IPv4Connectivity -eq "Internet";
                $Local:HasIPv6 = $_.IPv6Connectivity -eq "Internet";

                $Local:HasIPv4 -or $Local:HasIPv6
            } | Measure-Object | Select-Object -ExpandProperty Count) -gt 0;

        if ($Local:HasNetwork) {
            Write-Host "Network is already setup, skipping network setup...";
            return
        }

        Write-Host "No Wi-Fi connection found, creating profile..."

        [String]$Local:ProfileFile = "$env:TEMP\SetupWireless-profile.xml";
        If ($Local:ProfileFile | Test-Path) {
            Write-Host "Profile file exists, removing it...";
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
"

        if ($DryRun) {
            Write-Host "Dry run enabled, skipping profile creation..."
            Write-Host "Would have created profile file $Local:ProfileFile with contents:"
            Write-Host $Local:XmlContent
        } else {
            Write-Host "Creating profile file $Local:ProfileFile...";
            $Local:XmlContent > ($Local:ProfileFile);

            netsh wlan add profile filename="$($Local:ProfileFile)" | Out-Null
            netsh wlan show profiles $NetworkName key=clear | Out-Null
            netsh wlan connect name=$NetworkName | Out-Null
        }

        Write-Host "Waiting for network connection..."
        $Local:RetryCount = 0;
        while (-not (Test-Connection -Destination google.com -Count 1 -Quiet)) {
            If ($Local:RetryCount -ge 60) {
                Write-Host "Failed to connect to $NetworkName after 10 retries, aborting..."
                exit $Script:FAILED_TO_CONNECT
            }

            Start-Sleep -Seconds 1
            $Local:RetryCount += 1
        }

        Write-Host "Connected to $NetworkName."
    }
}

# If the script isn't located in the temp folder, copy it there and run it from there.
function Invoke-EnsureLocalScript {
    begin { Enter-Scope -Invocation $MyInvocation }
    end { Exit-Scope -Invocation $MyInvocation }

    process {
        [String]$Local:ScriptPath = $MyInvocation.PSScriptRoot;
        [String]$Local:TempPath = (Get-Item $env:TEMP).FullName;

        $Local:ScriptPath | Assert-NotNull -Message "Script path was null, this really shouldn't happen.";
        $Local:TempPath | Assert-NotNull -Message "Temp path was null, this really shouldn't happen.";

        if ($Local:ScriptPath -ne $Local:TempPath) {
            Write-Host "Copying script to temp folder...";
            [String]$Into = "$Local:TempPath\win_setup.ps1";

            try {
                Copy-Item -Path $MyInvocation.PSCommandPath -Destination $Into -Force;
            }
            catch {
                Write-Error "Failed to copy script to temp folder" -Category PermissionDenied;
            }

            Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -NoExit -File `"$Into`" -Phase $Phase -RecursionLevel $RecursionLevel"
            Write-Host "Exiting original process due to script being copied to temp folder...";
            exit 0;
        }
    }
}

# Get all required user input for the rest of the script to run automatically.
function Invoke-EnsureSetupInfo {
    begin { Enter-Scope -Invocation $MyInvocation }
    end { Exit-Scope -Invocation $MyInvocation }

    process {
        [String]$Local:File = "$($env:TEMP)\InstallInfo.json";

        If (Test-Path $Local:File) {
            Write-Host "Install Info exists, checking validity...";

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
                Write-Host "There was an issue with the install info, deleting the file for recreation...";
                Remove-Item -Path $Local:File -Force;
            }
        }

        Write-Host "No install info found, creating new install info...";

        $Local:Clients = (Get-SoapResponse -Uri (Get-BaseUrl "list_clients")).items.client;
        $Local:Clients | Assert-NotNull -Message "Failed to get clients from N-Able";

        $Local:FormattedClients = Get-FormattedName2Id -InputArr $Clients -IdExpr { $_.clientid }
        $Local:FormattedClients | Assert-NotNull -Message "Failed to format clients";

        $Local:SelectedClient;
        while ($null -eq $Local:SelectedClient) {
            $Local:Selection = $Local:FormattedClients | Out-GridView -Title "Select a client" -PassThru;
            if ($null -eq $Local:Selection) {
                Write-Host "No client was selected, re-running selection...";
            } else {
                $Local:SelectedClient = $Local:Selection;
            }
        }
        $Local:SelectedClient | Assert-NotNull -Message "Failed to select a client.";

        $Local:Sites = (Get-SoapResponse -Uri "$(Get-BaseUrl "list_sites")&clientid=$($SelectedClient.Id)").items.site;
        $Local:Sites | Assert-NotNull -Message "Failed to get sites from N-Able";

        $Local:FormattedSites = Get-FormattedName2Id -InputArr $Sites -IdExpr { $_.siteid };
        $Local:FormattedSites | Assert-NotNull -Message "Failed to format sites";

        $Local:SelectedSite;
        while ($null -eq $Local:SelectedSite) {
            $Local:Selection = $Local:FormattedSites | Out-GridView -Title "Select a site" -PassThru;
            if ($null -eq $Local:Selection) {
                Write-Host "No client was selected, re-running selection...";
            } else {
                $Local:SelectedClient = $Local:Selection;
            }
        }
        $Local:SelectedSite | Assert-NotNull -Message "Failed to select a site.";

        # TODO - Show a list of devices for the selected client so the user can confirm they're using the correct naming convention
        [String]$Local:DeviceName = Get-PromptInput -title "Device Name" -question "Enter a name for this device"

        [PSCustomObject]$Local:InstallInfo = @{
            "DeviceName" = $Local:DeviceName
            "ClientId"   = $Local:SelectedClient.Id
            "SiteId"     = $Local:SelectedSite.Id
            "Path"       = $Local:File
        };

        Write-Host "Saving install info to $Local:File...";
        try {
            $Local:InstallInfo | ConvertTo-Json | Out-File -FilePath $File -Force;
        } catch {
            Write-Error "There was an issue saving the install info to $Local:File" -Category PermissionDenied;
        }

        return $Local:InstallInfo
    }
}

# Make sure all required modules have been installed.
function Invoke-EnsureModulesInstalled {
    begin { Enter-Scope -Invocation $MyInvocation }
    end { Exit-Scope -Invocation $MyInvocation }

    process {
        Import-DownloadableModule -Name PSWindowsUpdate
    }
}

#endregion - Environment Setup

#region - Queue Functions

#region - Flag Settings
function Get-FlagPath([Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$Context) {
    begin { Enter-Scope -Invocation $MyInvocation }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:FlagPath }

    process {
        [String]$Local:FlagFolder = "$($env:TEMP)\Flags";
        if (-not (Test-Path $Local:FlagFolder)) {
            Write-Host "Creating flag folder $Local:FlagFolder...";
            New-Item -ItemType Directory -Path $Local:FlagFolder;
        }

        [String]$Local:FlagPath = "$Local:FlagFolder\$Context.flag";
        $Local:FlagPath
    }
}

function Set-Flag([Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$Context, [Object]$Data) {
    begin { Enter-Scope -Invocation $MyInvocation }
    end { Exit-Scope -Invocation $MyInvocation }

    process {
        $Context | Assert-NotNull -Message "Context was null";

        [String]$Flag = Get-FlagPath -Context $Context;
        New-Item -ItemType File -Path $Flag -Force;

        if ($null -ne $Data) {
            $Data | Out-File -FilePath $Flag -Force;
        }
    }
}

function Get-Flag([Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$Context) {
    begin { Enter-Scope -Invocation $MyInvocation }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:FlagResult }

    process {
        $Context | Assert-NotNull -Message "Context was null";

        [String]$Local:Flag = Get-FlagPath -Context $Context;
        [Boolean]$Local:FlagResult = Test-Path $Local:Flag

        $Local:FlagResult
    }
}

function Get-FlagData([Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$Context) {
    begin { Enter-Scope -Invocation $MyInvocation }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:FlagData }

    process {
        $Context | Assert-NotNull -Message "Context was null";

        [String]$Local:Flag = Get-FlagPath -Context $Context;
        [Boolean]$Local:FlagResult = Test-Path $Local:Flag

        if ($Local:FlagResult) {
            $Local:FlagData = Get-Content -Path $Local:Flag;
        }

        $Local:FlagData
    }
}

function Remove-Flag([Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$Context) {
    begin { Enter-Scope -Invocation $MyInvocation }
    end { Exit-Scope -Invocation $MyInvocation }

    process {
        $Context | Assert-NotNull -Message "Context was null";

        [String]$Local:Flag = Get-FlagPath -Context $Context;
        Remove-Item -Path $Local:Flag -Force -ErrorAction SilentlyContinue
    }
}

#region - Reboot Flag
function Set-RebootFlag { Set-Flag -Context "reboot" }
function Remove-RebootFlag { Remove-Flag -Context "reboot" }
function Get-RebootFlag {
    if (-not (Get-Flag -Context "reboot")) {
        return $false;
    }

    # Get the write time for the reboot flag file; if it was written before the computer started, we have reboot, return false;
    [DateTime]$Local:RebootFlagTime = (Get-Item (Get-FlagPath -Context "reboot")).LastWriteTime;
    [DateTime]$Local:StartTime = Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object -ExpandProperty LastBootUpTime;

    return $Local:RebootFlagTime -gt $Local:StartTime;
}
#endregion - Reboot Flag
#region - Running Flag
function Set-RunningFlag { Set-Flag -Context "running" -Data $PID }
function Remove-RunningFlag { Remove-Flag -Context "running" }
function Get-RunningFlag {
    if (-not (Get-Flag -Context "running")) {
        return $false;
    }

    # Check if the PID in the running flag is still running, if not, remove the flag and return false;
    [Int]$Local:RunningPID = Get-FlagData -Context "running";
    if (-not (Get-Process -Id $Local:RunningPID -ErrorAction SilentlyContinue)) {
        Remove-RunningFlag;
        return $false;
    }

    return $true;
}
#endregion - Running Flag

#endregion - Flag Settings

#region - Task Scheduler Implementation
function Set-StartupSchedule([String]$NextPhase, [switch]$Imediate, [String]$CommandPath = $MyInvocation.PSCommandPath) {
    begin { Enter-Scope -Invocation $MyInvocation }
    end { Exit-Scope -Invocation $MyInvocation }

    process {
        $Local:Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -WakeToRun;

        [String]$Local:RunningUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name;
        $Local:RunningUser | Assert-NotNull -Message "Running user was null, this really shouldn't happen.";
        $Local:Principal = New-ScheduledTaskPrincipal -UserId $Local:RunningUser -RunLevel Highest;

        switch ($Imediate) {
            $true { $Local:Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5); }
            $false { $Local:Trigger = New-ScheduledTaskTrigger -AtLogOn -User $Local:RunningUser; }
        }

        [Int]$Local:RecursionLevel = if ($Phase -eq $NextPhase) { $RecursionLevel + 1 } else { 0 };
        $Local:Action = New-ScheduledTaskAction `
            -Execute "powershell.exe" `
            -Argument "-ExecutionPolicy Bypass -NoExit -File `"$CommandPath`" -Phase $NextPhase -RecursionLevel $Local:RecursionLevel $(if ($DryRun) { "-DryRun" } else { " " })";

        $Local:Task = New-ScheduledTask `
            -Action $Local:Action `
            -Principal $Local:Principal `
            -Settings $Local:Settings `
            -Trigger $Local:Trigger;

        Register-ScheduledTask -TaskName $TaskName -InputObject $Task -ErrorAction Stop | Out-Null
    }
}
#endregion - Task Scheduler Implementation

function Remove-QueuedTask {
    begin { Enter-Scope $MyInvocation }
    end { Exit-Scope $MyInvocation }

    process {
        $Task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue;
        if ($null -ne $Task) {
            Write-Host "Removing scheduled task [$TaskName]...";
            Unregister-ScheduledTask -TaskName $TaskName -ErrorAction Stop -Confirm:$false | Out-Null;
        }
    }
}

function Add-QueuedTask(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$QueuePhase,
    [switch]$OnlyOnRebootRequired = $false
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        [Boolean]$Local:RequiresReboot = Get-RebootFlag;

        if ($OnlyOnRebootRequired -and (-not $Local:RequiresReboot)) {
            Write-Host "The device does not require a reboot before the $QueuePhase phase can be started, skipping queueing...";
            return;
        }

        # Schedule the task before possibly rebooting.
        Set-StartupSchedule -NextPhase $QueuePhase -Imediate:(-not $Local:RequiresReboot);

        if ($Local:RequiresReboot) {
            Write-Host "The device requires a reboot before the $QueuePhase phase can be started, rebooting in 15 seconds...";
            Write-Host "Press any key to cancel the reboot...";
            $Host.UI.RawUI.FlushInputBuffer();
            $Local:Countdown = 150;
            while ($Local:Countdown -gt 0) {
                if ([Console]::KeyAvailable) {
                    Write-Host "Key was pressed, canceling reboot.";
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
                Write-Host "Rebooting now...";

                Remove-RebootFlag;
                Restart-Computer -Force -WhatIf:$DryRun;
            } else {
                # Add flag about missing reboot
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
            Write-Host "Device name is already set to $Local:DeviceName.";
        } else {
            Write-Host "Device name is not set to $Local:DeviceName, setting it now...";
            Rename-Computer -NewName $Local:DeviceName -WhatIf:$DryRun;
            Set-RebootFlag;
        }
        #endregion - Device Name

        #region - Auto-Login
        [String]$Local:RegKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon";
        try {
            $ErrorActionPreference = "Stop";

            Set-ItemProperty -Path $Local:RegKey -Name "AutoAdminLogon" -Value 1 | Out-Null;
            Set-ItemProperty -Path $Local:RegKey -Name "DefaultUserName" -Value "localadmin" | Out-Null;
            Set-ItemProperty -Path $Local:RegKey -Name "DefaultPassword" -Value "" | Out-Null;
        } catch {
            Write-Error "Failed to set auto-login registry keys";
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
                    Write-Warning "Failed to process item [$Local:Item]";
                    try {
                        $ErrorActionPreference = "Stop";

                        if ($null -eq $FailedProcessItem) {
                            $Local:FailedItems.Add($Local:Item);
                        } else { $FailedProcessItem.InvokeReturnAsIs($Local:Item); }
                    } catch {
                        Write-Warning "Failed to process item [$Local:Item] in failed process item block";
                    }
                }

                $Local:PercentComplete += $Local:PercentPerItem;
            }
            Write-Progress -Activity $Local:ProgressActivity -PercentComplete 100 -Completed;

            if ($Local:FailedItems.Count -gt 0) {
                Write-Warning "Failed to process $($Local:FailedItems.Count) items";
                Write-Warning "Failed items: `n`t$($Local:FailedItems -join "`n`t")";
            }
        }
        function Stop-Services_HP {
            begin { Enter-Scope -Invocation $MyInvocation; }
            end { Exit-Scope -Invocation $MyInvocation; }

            process {
                [String[]]$Local:Services = @("HotKeyServiceUWP", "HPAppHelperCap", "HP Comm Recover", "HPDiagsCap", "HotKeyServiceUWP", "LanWlanWwanSwitchingServiceUWP", "HPNetworkCap", "HPSysInfoCap", "HP TechPulse Core");

                Write-Host -ForegroundColor Cyan "ℹ️ Disabling $($Services.Value.Count) services...";
                Invoke-Progress -GetItems { $Local:Services } -ProcessItem {
                    Param($Local:ServiceName)

                    try {
                        $ErrorActionPreference = 'Stop';
                        $Local:Instance = Get-Service -Name $Local:Service;
                    } catch {
                        Write-Host -ForegroundColor Yellow "⚠️ Skipped service $Local:Service as it isn't installed.";
                    }

                    if ($null -ne $Local:Instance) {
                        Write-Host -ForegroundColor Cyan "🛑 Stopping service $Local:Instance...";
                        try {
                            $ErrorActionPreference = 'Stop';
                            $Local:Instance | Stop-Service -Force -WhatIf:$DryRun -Confirm:$false;
                            Write-Host -ForegroundColor Green "✅ Stopped service $Local:Instance";
                        } catch {
                            Write-Warning -Message "❌ Failed to stop $Local:Instance";
                        }

                        Write-Host -ForegroundColor Yellow "🛑 Disabling service $Service...";
                        try {
                            $ErrorActionPreference = 'Stop';
                            $Local:Instance | Set-Service -StartupType Disabled -Force -WhatIf:$DryRun -Confirm:$false;
                            Write-Host -ForegroundColor Green "✅ Disabled service $Service";
                        } catch {
                            Write-Warning -Message "❌ Failed to disable $Service";
                        }
                    }
                };
            }
        }
        function Remove-Packages_HP {
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

                    $Local:Product = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq $Local:Package.Name };
                    if ($null -eq $Local:Product) {
                        throw "Can't find MSI Package for program [$($Local:Package.Name)]";
                    } else {
                        msiexec /x $Local:Product.IdentifyingNumber /quiet /noreboot | Out-Null;
                        Write-Host "Sucessfully removed program [$($Local:Package.Name)]";
                    }
                };

                # Fallback attempt 1 to remove HP Wolf Security using msiexec
                Try {
                    MsiExec /x "{0E2E04B0-9EDD-11EB-B38C-10604B96B11E}" /qn /norestart
                    Write-Host -Object "Fallback to MSI uninistall for HP Wolf Security initiated"
                } Catch {
                    Write-Warning -Object "Failed to uninstall HP Wolf Security using MSI - Error message: $($_.Exception.Message)"
                }

                # Fallback attempt 2 to remove HP Wolf Security using msiexec
                Try {
                    MsiExec /x "{4DA839F0-72CF-11EC-B247-3863BB3CB5A8}" /qn /norestart
                    Write-Host -Object "Fallback to MSI uninistall for HP Wolf 2 Security initiated"
                } Catch {
                    Write-Warning -Object  "Failed to uninstall HP Wolf Security 2 using MSI - Error message: $($_.Exception.Message)"
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
                    Write-Host "Sucessfully removed provisioned package [$($Package.DisplayName)]";
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

                    Remove-AppxPackage -Package $Package.PackageFullName -AllUsers -WhatIf:$DryRun;
                    Write-Host "Sucessfully removed appx-package [$($Package.Name)]";
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

                    pnputil /delete-driver $_.Driver /uninstall /force;
                    Write-Host "Removed driver: $($_.OriginalFileName.toString())";
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
        Remove-Packages_HP;

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
            Write-Host "Agent is already installed, skipping installation...";
            return $Local:NextPhase;
        }

        [String]$Local:ClientId = $Script:InstallInfo.ClientId;
        [String]$Local:SiteId = $Script:InstallInfo.SiteId;
        [String]$Local:Uri = "https://system-monitor.com/api/?apikey=$ApiKey&service=get_site_installation_package&endcustomerid=$ClientId&siteid=$SiteId&os=windows&type=remote_worker";

        [String]$Local:OutputFolder = Get-TempFolder -Name "Agent";
        [String]$Local:OutputZip = "$Local:OutputFolder\agent.zip";
        [String]$Local:OutputExtracted = "$Local:OutputFolder\unpacked";

        Write-Host "Downloading agent from [$Local:Uri]";
        try {
            $ErrorActionPreference = "Stop";
            Invoke-WebRequest -Uri $Local:Uri -OutFile $Local:OutputZip -UseBasicParsing;
        } catch {
            Write-Host -ForegroundColor Red "Failed to download agent from [$Local:Uri]";
            Invoke-FailedExit -ExitCode $Script:AGENT_FAILED_DOWNLOAD;
        }

        Write-Host "Expanding archive [$Local:OutputZip] to [$Local:OutputExtracted]...";
        try {
            $ErrorActionPreference = "Stop";
            Expand-Archive -Path $Local:OutputZip -DestinationPath $Local:OutputExtracted;
        } catch {
            Write-Host -ForegroundColor Red "Failed to expand archive [$Local:OutputZip] to [$Local:OutputExtracted]";
            Invoke-FailedExit -ExitCode $Script:AGENT_FAILED_EXPAND;
        }

        Write-Host "Finding agent executable in [$Local:OutputExtracted]...";
        try {
            $ErrorActionPreference = "Stop";
            [String]$Local:OutputExe = Get-ChildItem -Path $Local:OutputExtracted -Filter "*.exe" -File;

            # For some reason theres an issue with the path being an array
            # When being downloaded within the same session, but not within the function
            # Only once the function is returned does the value become an array.
            # This seems to be a bug with powershell, but I'm not sure.
            # [String]$Local:OutputExe = $null;
            # foreach ($Local:SubPath in $Local:Output) {
            #     $LocaL:OutputExe = $Local:SubPath;
            # }

            $Local:OutputExe | Assert-NotNull -Message "Failed to find agent executable in [$OutputExtracted]";
        } catch {
            Write-Host -ForegroundColor Red "Failed to find agent executable in [$OutputExtracted]";
            Invoke-FailedExit -ExitCode $Script:AGENT_FAILED_FIND;
        }

        Write-Host "Installing agent from [$Local:OutputExe]...";
        switch ($DryRun) {
            $true { Write-Host -ForegroundColor Cyan "Dry run enabled, skipping agent installation..."; }
            $false {
                try {
                    # Might need .FullName
                    $Local:Installer = Start-Process -FilePath $Local:OutputExe -Wait;
                    $Local:Installer.ExitCode | Assert-Equals -Expected 0 -Message "Agent installer failed with exit code [$($Local:Installer.ExitCode)]";

                    Set-RebootFlag;
                } catch {
                    Write-Host -ForegroundColor Red "Failed to install agent from [$Local:OutputExe]";
                    Invoke-FailedExit -ExitCode $Script:AGENT_FAILED_INSTALL;
                }
            }
        }

        while ($true) {
            $Local:AgentStatus = Get-Sevice -Name $Local:AgentServiceName -ErrorAction SilentlyContinue;
            if ($Local:AgentStatus -and $Local:AgentStatus.Status -eq "Running") {
                Write-Host -ForegroundColor Cyan "The agent has been installed and running, current status is [$Local:AgentStatus]...";
                break;
            }

            Start-Sleep -Milliseconds 100;
        }

        Write-Host -ForegroundColor Cyan "Unable to determine when the agent is fully installed, sleeping for 5 minutes...";
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

        Get-WindowsUpdate -Install -AcceptAll -AutoReboot:$false -IgnoreReboot -IgnoreUserInput -Confirm:$false -WhatIf:$DryRun;
        Set-RebootFlag;

        return $Local:NextPhase;
    }
}

function Invoke-PhaseFinish {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:NextPhase; }

    process {
        [String]$Local:NextPhase = $null;

        # TODO :: Check if everything is completed and configured correctly, if not maybe re-run a phase?

        return $Local:NextPhase;
    }
}

#endregion - Phase Functions

#region - Exit Functions

function Invoke-FailedExit([Parameter(Mandatory)][ValidateNotNullOrEmpty()][Int]$ExitCode, [System.Management.Automation.ErrorRecord]$ErrorRecord) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        Remove-QueuedTask;
        Remove-RunningFlag;

        If ($null -ne $ErrorRecord) {
            [System.Management.Automation.InvocationInfo]$Local:InvocationInfo = $ErrorRecord.InvocationInfo;
            $Local:InvocationInfo | Assert-NotNull -Message "Invocation info was null, how am i meant to find error now??";

            [System.Exception]$Local:RootCause = $ErrorRecord.Exception;
            while ($null -ne $Local:RootCause.InnerException) {
                $Local:RootCause = $Local:RootCause.InnerException;
            }

            Write-Host -ForegroundColor Red $Local:InvocationInfo.PositionMessage;
            Write-Host -ForegroundColor Red $Local:RootCause.Message;
        }

        # TODO :: Better recovery for failed exits
        Write-Host -ForegroundColor Red "Failed to complete phase [$Phase], exiting...";
        Exit $ExitCode;
    }
}

function Invoke-QuickExit {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        Remove-RunningFlag;

        Write-Host -ForegroundColor Red "Exiting...";
        Exit 0;
    }
}

#endregion - Exit Functions

Import-Module '../../common/Environment.psm1';
Invoke-RunMain $MyInvocation {
    Trap {
        Write-Host -ForegroundColor Red -Object "Unknown error occured, exiting...";
        Write-Host -ForegroundColor Red -Object $_;
        Write-Host -ForegroundColor Red -Object $_.Exception;
        Invoke-FailedExit -ExitCode 9999;
    }

    # Ensure only one process is running at a time.
    If (Get-RunningFlag) {
        Write-Host -ForegroundColor Red "The script is already running in another session, exiting...";
        exit $Script:ALREADY_RUNNING;
    } else {
        Set-RunningFlag;
    }

    try {
        Invoke-EnsureLocalScript;
        Invoke-EnsureNetworkSetup;
        Invoke-EnsureModulesInstalled;
        $Local:InstallInfo = Invoke-EnsureSetupInfo;
    } catch {
        Invoke-FailedExit -ExitCode $Script:FAILED_SETUP_ENVIRONMENT;
    }

    Invoke-ConfigureDeviceFromSetup -InstallInfo $Local:InstallInfo;
    # Queue this phase to run again if a restart is required by one of the environment setups.
    Add-QueuedTask -QueuePhase $Phase -OnlyOnRebootRequired;

    [String]$Local:NextPhase = $null;
    switch ($Phase) {
        "configure" { $Local:NextPhase = Invoke-PhaseConfigure -InstallInfo $Local:InstallInfo; }
        "cleanup" { $Local:NextPhase = Invoke-PhaseCleanup; }
        "install" { $Local:NextPhase = Invoke-PhaseInstall -InstallInfo $Local:InstallInfo; }
        "update" { $Local:NextPhase = Invoke-PhaseUpdate; }
        "finish" { $Local:NextPhase = Invoke-PhaseFinish; }
    }

    # Should only happen when we are done and there is nothing else to queue.
    if ($null -eq $Local:NextPhase) {
        Invoke-QuickExit;
    }

    Add-QueuedTask -QueuePhase $Local:NextPhase;
    Invoke-QuickExit;
}
