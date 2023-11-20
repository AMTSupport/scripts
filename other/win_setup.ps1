#Requires -Version 5.1
#Requires -RunAsAdministrator

# Windows Setup screen raw inputs
# enter,down,enter,enter,tab,tab,tab,enter,tab,tab,tab,tab,tab,tab,enter,tab,tab,tab,tab,enter,localadmin,enter,enter,enter,enter,tab,tab,tab,tab,tab,enter,tab,tab,tab,tab,enter

# After windows setup
# windows,powershell,right,down,enter,left,enter,Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process,enter,a,enter,D:\win_setup.ps1,enter

Param (
    [Parameter()]
    [switch]$DryRun,

    [Parameter()]

    [ValidateSet("Configure", "Cleanup", "Install", "Update", "Finish")]
    [String]$Phase = "Configure",

    [Parameter(DontShow)]
    [ValidateLength(32, 32)]
    [String]$ApiKey = "",

    [Parameter(DontShow)]
    [ValidateNotNullOrEmpty()]
    [String]$Endpoint = "system-monitor.com",

    [Parameter(DontShow)]
    [ValidateNotNullOrEmpty()]
    [String]$NetworkName = "Guests",

    [Parameter(DontShow)]
    [ValidateNotNullOrEmpty()]
    [String]$NetworkPassword = "",

    [Parameter(DontShow)]
    [ValidateNotNullOrEmpty()]
    [String]$TaskName = "SetupScheduledTask",

    [Parameter(DontShow)]
    [ValidateNotNullOrEmpty()]
    [Int]$RecursionLevel = 0
)

# Section Start - Utility Functions

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

function Local:Assert-NotNull([Parameter(Mandatory, ValueFromPipeline)][Object]$Object, [String]$Message) {
    if ($null -eq $Object -or $Object -eq "") {
        if ($null -eq $Message) {
            Write-Host -ForegroundColor Red -Object "Object is null";
            Local:Invoke-FailedExit -ExitCode $Script:NULL_ARGUMENT;
        } else {
            Write-Host -ForegroundColor Red -Object $Message;
            Local:Invoke-FailedExit -ExitCode $Script:NULL_ARGUMENT;
        }
    }
}

function Local:Assert-Equals([Parameter(Mandatory, ValueFromPipeline)][Object]$Object, [Parameter(Mandatory)][Object]$Expected, [String]$Message) {
    if ($Object -ne $Expected) {
        if ($null -eq $Message) {
            Write-Host -ForegroundColor Red -Object "Object [$Object] does not equal expected value [$Expected]";
            Local:Invoke-FailedExit -ExitCode $Script:FAILED_EXPECTED_VALUE;
        } else {
            Write-Host -ForegroundColor Red -Object $Message;
            Local:Invoke-FailedExit -ExitCode $Script:FAILED_EXPECTED_VALUE;
        }
    }
}


function Local:Get-ScopeFormatted([Parameter(Mandatory)][System.Management.Automation.InvocationInfo]$Invocation) {
    $Invocation | Local:Assert-NotNull "Invocation was null";

    [String]$ScopeName = $Invocation.MyCommand.Name;
    [String]$ScopeName = if ($null -ne $ScopeName) { "Scope: $ScopeName" } else { "Scope: Unknown" };
    return $ScopeName
}

function Local:Enter-Scope([Parameter(Mandatory)][System.Management.Automation.InvocationInfo]$Invocation) {
    $Invocation | Local:Assert-NotNull "Invocation was null";

    [String]$Local:ScopeName = Local:Get-ScopeFormatted -Invocation $Invocation;
    $Local:Params = $Invocation.BoundParameters
    if ($null -ne $Params -and $Params.Count -gt 0) {
        [String[]]$Local:ParamsFormatted = $Params.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)" } | Join-String -Separator "`n`t";
        [String]$Local:ParamsFormatted = "Parameters: $ParamsFormatted"
    }
    else {
        [String]$Local:ParamsFormatted = "Parameters: None"
    }

    Write-Verbose "Entered Scope`n`t$ScopeName`n`t$ParamsFormatted";
}

function Local:Exit-Scope([Parameter(Mandatory)][System.Management.Automation.InvocationInfo]$Invocation, [Object]$ReturnValue) {
    $Invocation | Local:Assert-NotNull "Invocation was null";

    [String]$Local:ScopeName = Local:Get-ScopeFormatted -Invocation $Invocation;
    [String]$Local:ReturnValueFormatted = if ($null -ne $ReturnValue) { "Return Value: $ReturnValue" } else { "Return Value: None" };

    Write-Verbose "Exited Scope`n`t$ScopeName`n`t$ReturnValueFormatted";
}

function Get-PromptInput {
    Param(
        [Parameter(Mandatory = $true)]
        [String]$title,

        [Parameter(Mandatory = $true)]
        [String]$question
    )

    $Host.UI.RawUI.ForegroundColor = 'Yellow'
    $Host.UI.RawUI.BackgroundColor = 'Black'

    Write-Host $title
    Write-Host "$($question): " -NoNewline

    $Host.UI.RawUI.FlushInputBuffer();
    $userInput = $Host.UI.ReadLine()

    $Host.UI.RawUI.ForegroundColor = 'White'
    $Host.UI.RawUI.BackgroundColor = 'Black'
    return $userInput
}

function Get-SoapResponse($Uri) {
    begin { Local:Enter-Scope $MyInvocation }

    process {
        $ContentType = "text/xml;charset=`"utf-8`""
        $Method = "GET"
        $Response = Invoke-RestMethod -Uri $Uri -ContentType $ContentType -Method $Method
        [System.Xml.XmlElement]$ParsedResponse = $Response.result

        $ParsedResponse
    }

    end { Local:Exit-Scope $MyInvocation }
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
function Local:Invoke-EnsureNetworkSetup {
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
        while (-not (Test-Connection -ComputerName google.com -Count 1 -Quiet)) {
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
function Local:Invoke-EnsureLocalScript {
    begin { Local:Enter-Scope -Invocation $MyInvocation }
    end { Local:Exit-Scope -Invocation $MyInvocation }

    process {
        [String]$Local:ScriptPath = $MyInvocation.PSScriptRoot;
        [String]$Local:TempPath = (Get-Item $env:TEMP).FullName;

        $Local:ScriptPath | Local:Assert-NotNull "Script path was null, this really shouldn't happen.";
        $Local:TempPath | Local:Assert-NotNull "Temp path was null, this really shouldn't happen.";

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

function Local:Invoke-EnsureFlags {
    begin { Local:Enter-Scope -Invocation $MyInvocation }
    end { Local:Exit-Scope -Invocation $MyInvocation }

    process {
        If (Local:Get-RebootFlag) {

        }
    }
}

# Get all required user input for the rest of the script to run automatically.
function Local:Invoke-EnsureSetupInfo {
    begin { Local:Enter-Scope -Invocation $MyInvocation }
    end { Local:Exit-Scope -Invocation $MyInvocation }

    process {
        [String]$Local:File = "$($env:TEMP)\InstallInfo.json";

        If (Test-Path $Local:File) {
            Write-Host "Install Info exists, checking validity...";

            try {
                [PSCustomObject]$Local:InstallInfo = Get-Content -Path $Local:File -Raw | ConvertFrom-Json;
                $Local:InstallInfo | Local:Assert-NotNull "Install info was null";

                [String]$Local:DeviceName = $Local:InstallInfo.DeviceName;
                $Local:DeviceName | Local:Assert-NotNull "Device name was null";

                [String]$Local:ClientId = $Local:InstallInfo.ClientId;
                $Local:ClientId | Local:Assert-NotNull "Client id was null";

                [String]$Local:SiteId = $Local:InstallInfo.SiteId;
                $Local:SiteId | Local:Assert-NotNull "Site id was null";

                [String]$Local:Path = $Local:InstallInfo.Path;
                $Local:Path | Local:Assert-NotNull "Path was null";


                return $Local:InstallInfo;
            } catch {
                Write-Host "There was an issue with the install info, deleting the file for recreation...";
                Remove-Item -Path $Local:File -Force;
            }
        }

        Write-Host "No install info found, creating new install info...";

        $Local:Clients = (Get-SoapResponse -Uri (Get-BaseUrl "list_clients")).items.client;
        $Local:Clients | Local:Assert-NotNull "Failed to get clients from N-Able";

        $Local:FormattedClients = Get-FormattedName2Id -InputArr $Clients -IdExpr { $_.clientid }
        $Local:FormattedClients | Local:Assert-NotNull "Failed to format clients";

        $Local:SelectedClient;
        while ($null -eq $Local:SelectedClient) {
            $Local:Selection = $Local:FormattedClients | Out-GridView -Title "Select a client" -PassThru;
            if ($null -eq $Local:Selection) {
                Write-Host "No client was selected, re-running selection...";
            } else {
                $Local:SelectedClient = $Local:Selection;
            }
        }
        $Local:SelectedClient | Local:Assert-NotNull "Failed to select a client.";

        $Local:Sites = (Get-SoapResponse -Uri "$(Get-BaseUrl "list_sites")&clientid=$($SelectedClient.Id)").items.site;
        $Local:Sites | Local:Assert-NotNull "Failed to get sites from N-Able";

        $Local:FormattedSites = Get-FormattedName2Id -InputArr $Sites -IdExpr { $_.siteid };
        $Local:FormattedSites | Local:Assert-NotNull "Failed to format sites";

        $Local:SelectedSite;
        while ($null -eq $Local:SelectedSite) {
            $Local:Selection = $Local:FormattedSites | Out-GridView -Title "Select a site" -PassThru;
            if ($null -eq $Local:Selection) {
                Write-Host "No client was selected, re-running selection...";
            } else {
                $Local:SelectedClient = $Local:Selection;
            }
        }
        $Local:SelectedSite | Local:Assert-NotNull "Failed to select a site.";

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
function Local:Invoke-EnsureModulesInstalled {
    begin { Local:Enter-Scope -Invocation $MyInvocation }
    end { Local:Exit-Scope -Invocation $MyInvocation }

    process {
        Import-DownloadableModule -Name PSWindowsUpdate
    }
}

#endregion - Environment Setup

#region - Queue Functions

#region - Flag Settings
function Local:Get-FlagPath([Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$Context) {
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

function Local:Set-Flag([Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$Context, [Object]$Data) {
    begin { Enter-Scope -Invocation $MyInvocation }
    end { Exit-Scope -Invocation $MyInvocation }

    process {
        $Context | Local:Assert-NotNull "Context was null";

        [String]$Flag = Local:Get-FlagPath -Context $Context;
        New-Item -ItemType File -Path $Flag -Force;

        if ($null -ne $Data) {
            $Data | Out-File -FilePath $Flag -Force;
        }
    }
}

function Local:Get-Flag([Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$Context) {
    begin { Enter-Scope -Invocation $MyInvocation }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:FlagResult }

    process {
        $Context | Local:Assert-NotNull "Context was null";

        [String]$Local:Flag = Local:Get-FlagPath -Context $Context;
        [Boolean]$Local:FlagResult = Test-Path $Local:Flag

        $Local:FlagResult
    }
}

function Local:Get-FlagData([Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$Context) {
    begin { Enter-Scope -Invocation $MyInvocation }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:FlagData }

    process {
        $Context | Local:Assert-NotNull "Context was null";

        [String]$Local:Flag = Local:Get-FlagPath -Context $Context;
        [Boolean]$Local:FlagResult = Test-Path $Local:Flag

        if ($Local:FlagResult) {
            $Local:FlagData = Get-Content -Path $Local:Flag;
        }

        $Local:FlagData
    }
}

function Local:Remove-Flag([Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$Context) {
    begin { Enter-Scope -Invocation $MyInvocation }
    end { Exit-Scope -Invocation $MyInvocation }

    process {
        $Context | Local:Assert-NotNull "Context was null";

        [String]$Local:Flag = Local:Get-FlagPath -Context $Context;
        Remove-Item -Path $Local:Flag -Force -ErrorAction SilentlyContinue
    }
}

#region - Reboot Flag
function Local:Set-RebootFlag { Local:Set-Flag -Context "reboot" }
function Local:Remove-RebootFlag { Local:Remove-Flag -Context "reboot" }
function Local:Get-RebootFlag {
    if (-not (Local:Get-Flag -Context "reboot")) {
        return $false;
    }

    # Get the write time for the reboot flag file; if it was written before the computer started, we have reboot, return false;
    [DateTime]$Local:RebootFlagTime = (Get-Item (Local:Get-FlagPath -Context "reboot")).LastWriteTime;
    [DateTime]$Local:StartTime = Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object -ExpandProperty LastBootUpTime;

    return $Local:RebootFlagTime -gt $Local:StartTime;
}
#endregion - Reboot Flag
#region - Running Flag
function Local:Set-RunningFlag { Local:Set-Flag -Context "running" -Data $PID }
function Local:Remove-RunningFlag { Local:Remove-Flag -Context "running" }
function Local:Get-RunningFlag {
    if (-not (Local:Get-Flag -Context "running")) {
        return $false;
    }

    # Check if the PID in the running flag is still running, if not, remove the flag and return false;
    [Int]$Local:RunningPID = Local:Get-FlagData -Context "running";
    if (-not (Get-Process -Id $Local:RunningPID -ErrorAction SilentlyContinue)) {
        Local:Remove-RunningFlag;
        return $false;
    }

    return $true;
}
#endregion - Running Flag

#endregion - Flag Settings

#region - Task Scheduler Implementation
function Local:Set-StartupSchedule([String]$NextPhase, [switch]$Imediate, [String]$CommandPath = $MyInvocation.PSCommandPath) {
    begin { Enter-Scope -Invocation $MyInvocation }
    end { Exit-Scope -Invocation $MyInvocation }

    process {
        $Local:Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -WakeToRun;

        [String]$Local:RunningUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name;
        $Local:RunningUser | Local:Assert-NotNull "Running user was null, this really shouldn't happen.";
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

function Local:Remove-QueuedTask {
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

function Local:Add-QueuedTask(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$QueuePhase,
    [switch]$OnlyOnRebootRequired = $false
) {
    begin { Local:Enter-Scope -Invocation $MyInvocation; }
    end { Local:Exit-Scope -Invocation $MyInvocation; }

    process {
        [Boolean]$Local:RequiresReboot = Get-RebootFlag;

        if ($OnlyOnRebootRequired -and (-not $Local:RequiresReboot)) {
            Write-Host "The device does not require a reboot before the $QueuePhase phase can be started, skipping queueing...";
            return;
        }

        # Schedule the task before possibly rebooting.
        Local:Set-StartupSchedule -NextPhase $QueuePhase -Imediate:(-not $Local:RequiresReboot);

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

                Local:Remove-RebootFlag;
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
    begin { Local:Enter-Scope -Invocation $MyInvocation; }
    end { Local:Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:NextPhase; }

    process {
        $InstallInfo | Local:Assert-NotNull "Install info was null";

        #region - Device Name
        [String]$Local:DeviceName = $InstallInfo.DeviceName;
        $Local:DeviceName | Local:Assert-NotNull "Device name was null";

        [String]$Local:ExistingName = $env:COMPUTERNAME;
        $Local:ExistingName | Local:Assert-NotNull "Existing name was null"; # TODO :: Alternative method of getting existing name if $env:COMPUTERNAME is null

        if ($Local:ExistingName -eq $Local:DeviceName) {
            Write-Host "Device name is already set to $Local:DeviceName.";
        } else {
            Write-Host "Device name is not set to $Local:DeviceName, setting it now...";
            Rename-Computer -NewName $Local:DeviceName -WhatIf:$DryRun;
            Local:Set-RebootFlag;
        }
        #endregion - Device Name

        #region - Auto-Login
        [String]$Local:RegKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon";
        try {
            $ErrorActionPreference = "Stop";

            Set-ItemProperty -Path $Local:RegKey -Name "AutoAdminLogon" -Value 1 | Out-Null;
            Set-ItemProperty -Path $Local:RegKey -Name "DefaultUserName" -Value "localadmin" | Out-Null;
            Set-ItemProperty -Path $Local:RegKey -Name "DefaultPassword" -Value "" | Out-Null;
        }
        catch {
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
        function Stop-HPServices {
            begin { Enter-Scope -Invocation $MyInvocation; }
            end { Exit-Scope -Invocation $MyInvocation; }

            process {
                [String[]]$Local:Services = @("HotKeyServiceUWP", "HPAppHelperCap", "HP Comm Recover", "HPDiagsCap", "HotKeyServiceUWP", "LanWlanWwanSwitchingServiceUWP", "HPNetworkCap", "HPSysInfoCap", "HP TechPulse Core");
                foreach ($Local:Service in $Local:Services) {
                    Write-Host "Stopping service [$Local:Service]...";
                    if (Get-Service -Name $Local:Service -ErrorAction SilentlyContinue) {
                        Stop-Service -Name $Local:Service -Force -WhatIf:$DryRun -Confirm:$false;
                        Set-Service -Name $Local:Service -StartupType Disabled -WhatIf:$DryRun;
                    }
                }
            }
        }
        function Remove-Packages {
            begin { Enter-Scope -Invocation $MyInvocation; }
            end { Exit-Scope -Invocation $MyInvocation; }

            process {
                [String]$Local:ProgressActivity = "Remove-Packages";
                [String[]]$Local:UninstallablePrograms = @(
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

                Write-Progress -Activity $Local:ProgressActivity -CurrentOperation "Getting installed programs..." -PercentComplete 0;
                $Local:InstalledPrograms = Get-Package | Where-Object { $Local:UninstallablePrograms -contains $_.Name };
                Write-Progress -Activity $Local:ProgressActivity -PercentComplete 10;

                if ($null -eq $Local:InstalledPrograms -or $Local:InstalledPrograms.Count -eq 0) {
                    Write-Progress -Activity $Local:ProgressActivity -Status "No installed programs found for HP." -PercentComplete 100 -Completed;
                    return;
                }
                else {
                    Write-Progress -Activity $Local:ProgressActivity -Status "Removing $($Local:InstalledPrograms.Count) HP bloatware programs...";
                }

                $Local:PercentPerPackage = 90 / $Local:InstalledPrograms.Count;
                $Local:PercentComplete = 10;
                foreach ($Local:Program in $Local:InstalledPrograms) {
                    Write-Progress -Activity $Local:ProgressActivity -CurrentOperation "Removing program [$($Local:Program.Name)]..." -PercentComplete $Local:PercentComplete;

                    try {
                        $ErrorActionPreference = "Stop";

                        $Local:Program | Uninstall-Package -AllVersions -Force -WhatIf:$DryRun | Out-Null;
                        Write-Host "Sucessfully removed program [$($Local:Program.Name)]";
                    }
                    catch {
                        Write-Warning "Failed to remove program [$($Local:Package.Name)]";
                        Write-Host "Attempting to uninstall as MSI Package: $($Local:Package.Name)";

                        try {
                            $Local:Product = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq $Local:Package.Name };
                            if ($null -eq $Local:Product) {
                                Write-Warning "Can't find MSI Package for program [$($Local:Package.Name)]";
                            }
                            else {
                                msiexec /x $Local:Product.IdentifyingNumber /quiet /noreboot | Out-Null;
                                Write-Host "Sucessfully removed program [$($Local:Package.Name)]";
                            }
                        }
                        catch {
                            Write-Warning "Failed to remove program [$($Local:Package.Name)]";
                        }
                    }

                    $Local:PercentComplete += $Local:PercentPerPackage;
                }

                # Fallback attempt 1 to remove HP Wolf Security using msiexec
                Try {
                    MsiExec /x "{0E2E04B0-9EDD-11EB-B38C-10604B96B11E}" /qn /norestart
                    Write-Host -Object "Fallback to MSI uninistall for HP Wolf Security initiated"
                }
                Catch {
                    Write-Warning -Object "Failed to uninstall HP Wolf Security using MSI - Error message: $($_.Exception.Message)"
                }

                # Fallback attempt 2 to remove HP Wolf Security using msiexec
                Try {
                    MsiExec /x "{4DA839F0-72CF-11EC-B247-3863BB3CB5A8}" /qn /norestart
                    Write-Host -Object "Fallback to MSI uninistall for HP Wolf 2 Security initiated"
                }
                Catch {
                    Write-Warning -Object  "Failed to uninstall HP Wolf Security 2 using MSI - Error message: $($_.Exception.Message)"
                }
            }
        }
        function Remove-ProvisionedPackages {
            begin { Enter-Scope -Invocation $MyInvocation; }
            end { Exit-Scope -Invocation $MyInvocation; }

            process {
                [String]$Local:ProgressActivity = "Remove-ProvisionedPackages";
                [String]$Local:HPIdentifier = "AD2F1837";

                Write-Progress -Activity $Local:ProgressActivity -CurrentOperation "Getting provisioned packages..." -PercentComplete 0;
                [Object[]]$Local:ProvisionedPackages = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -match "^$Local:HPIdentifier" };
                Write-Progress -Activity $Local:ProgressActivity -CurrentOperation "Getting provisioned packages..." -PercentComplete 10;

                if ($null -eq $Local:ProvisionedPackages -or $Local:ProvisionedPackages.Count  -eq 0) {
                    Write-Progress -Activity $Local:ProgressActivity -Status "No provisioned packages found for HP." -PercentComplete 100 -Completed;
                    return;
                } else {
                    Write-Progress -Activity $Local:ProgressActivity -Status "Removing $($Local:ProvisionedPackages.Count) HP bloatware provisioned packages...";
                }

                $Local:PercentPerPackage = 90 / $Local:ProvisionedPackages.Count;
                $Local:PercentComplete = 10;
                foreach ($Local:Package in $Local:ProvisionedPackages) {
                    Write-Progress -Activity $Local:ProgressActivity -CurrentOperation "Removing provisioned package [$($Local:Package.DisplayName)]..." -PercentComplete $Local:PercentComplete;

                    try {
                        $ErrorActionPreference = "Stop";

                        Remove-AppxProvisionedPackage -PackageName $Local:Package.PackageName -Online | Out-Null;
                        Write-Host "Sucessfully removed provisioned package [$($Local:Package.DisplayName)]";
                    } catch {
                        Write-Warning "Failed to remove provisioned package [$($Local:Package.DisplayName)]";
                        Write-Host -ForegroundColor Red $_
                    }

                    $Local:PercentComplete += $Local:PercentPerPackage;
                }
            }
        }
        function Remove-AppxPackages {
            begin { Enter-Scope -Invocation $MyInvocation; }
            end { Exit-Scope -Invocation $MyInvocation; }

            process {
                [String]$Local:ProgressActivity = "Remove-AppxPackages";
                [String]$Local:HPIdentifier = "AD2F1837";

                Write-Progress -Activity $Local:ProgressActivity -CurrentOperation "Getting provisioned packages..." -PercentComplete 0;
                [Object[]]$Local:AppxPackages = Get-AppxPackage -AllUsers | Where-Object { $_.DisplayName -match "^$Local:HPIdentifier" };
                Write-Progress -Activity $Local:ProgressActivity -CurrentOperation "Getting provisioned packages..." -PercentComplete 10;

                if ($null -eq $Local:AppxPackages -or $Local:AppxPackages.Count  -eq 0) {
                    Write-Progress -Activity $Local:ProgressActivity -Status "No appx-packages found for HP." -PercentComplete 100 -Completed;
                    return;
                } else {
                    Write-Progress -Activity $Local:ProgressActivity -Status "Removing $($Local:AppxPackages.Count) HP bloatware appx-packages...";
                }

                $Local:PercentPerPackage = 90 / $Local:AppxPackages.Count;
                $Local:PercentComplete = 10;
                foreach ($Local:Package in $Local:AppxPackages) {
                    Write-Progress -Activity $Local:ProgressActivity -CurrentOperation "Removing appx-package [$($Local:Package.DisplayName)]..." -PercentComplete $Local:PercentComplete;

                    try {
                        $ErrorActionPreference = "Stop";

                        Remove-AppxPackage -Package $Local:Package.PackageFullName -AllUsers | Out-Null;
                        Write-Host "Sucessfully removed appx-package [$($Local:Package.DisplayName)]";
                    } catch {
                        Write-Warning "Failed to remove appx-package [$($Local:Package.DisplayName)]";
                        Write-Host -ForegroundColor Red $_
                    }

                    $Local:PercentComplete += $Local:PercentPerPackage;
                }

            }
        }

        Stop-HPServices;
        Remove-Packages;
        Remove-ProvisionedPackages;
        Remove-AppxPackages;

        # Queue next phase as self if still needed for Wolf uninstall.
        [String]$Local:NextPhase = "Install";
        return $Local:NextPhase;
    }
}

# Install the agent and any other required software.
function Invoke-PhaseInstall([Parameter(Mandatory)][ValidateNotNullOrEmpty()][PSCustomObject]$InstallInfo) {
    begin { Local:Enter-Scope -Invocation $MyInvocation; }
    end { Local:Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:NextPhase; }

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
            Local:Invoke-FailedExit -ExitCode $Script:AGENT_FAILED_DOWNLOAD;
        }

        Write-Host "Expanding archive [$Local:OutputZip] to [$Local:OutputExtracted]...";
        try {
            $ErrorActionPreference = "Stop";
            Expand-Archive -Path $Local:OutputZip -DestinationPath $Local:OutputExtracted;
        } catch {
            Write-Host -ForegroundColor Red "Failed to expand archive [$Local:OutputZip] to [$Local:OutputExtracted]";
            Local:Invoke-FailedExit -ExitCode $Script:AGENT_FAILED_EXPAND;
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

            $Local:OutputExe | Local:Assert-NotNull "Failed to find agent executable in [$OutputExtracted]";
        } catch {
            Write-Host -ForegroundColor Red "Failed to find agent executable in [$OutputExtracted]";
            Local:Invoke-FailedExit -ExitCode $Script:AGENT_FAILED_FIND;
        }

        Write-Host "Installing agent from [$Local:OutputExe]...";
        switch ($DryRun) {
            $true { Write-Host -ForegroundColor Cyan "Dry run enabled, skipping agent installation..."; }
            $false {
                try {
                    # Might need .FullName
                    $Local:Installer = Start-Process -FilePath $Local:OutputExe -Wait;
                    $Local:Installer.ExitCode | Local:Assert-Equals -Expected 0 -Message "Agent installer failed with exit code [$($Local:Installer.ExitCode)]";

                    Local:Set-RebootFlag;
                } catch {
                    Write-Host -ForegroundColor Red "Failed to install agent from [$Local:OutputExe]";
                    Local:Invoke-FailedExit -ExitCode $Script:AGENT_FAILED_INSTALL;
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
    begin { Local:Enter-Scope -Invocation $MyInvocation; }
    end { Local:Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:NextPhase; }

    process {
        [String]$Local:NextPhase = if ($RecursionLevel -ge 2) { "Finish" } else { "Update" };

        Get-WindowsUpdate -Install -AcceptAll -AutoReboot:$false -IgnoreReboot -IgnoreUserInput -Confirm:$false -WhatIf:$DryRun;
        Local:Set-RebootFlag;

        return $Local:NextPhase;
    }
}

function Invoke-PhaseFinish {
    begin { Local:Enter-Scope -Invocation $MyInvocation; }
    end { Local:Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:NextPhase; }

    process {
        [String]$Local:NextPhase = $null;

        # TODO :: Check if everything is completed and configured correctly, if not maybe re-run a phase?

        return $Local:NextPhase;
    }
}

#endregion - Phase Functions

#region - Exit Functions

function Local:Invoke-FailedExit([Parameter(Mandatory)][ValidateNotNullOrEmpty()][Int]$ExitCode) {
    begin { Local:Enter-Scope -Invocation $MyInvocation; }
    end { Local:Exit-Scope -Invocation $MyInvocation; }

    process {
        Local:Remove-QueuedTask;
        Local:Remove-RunningFlag;

        # TODO :: Better recovery for failed exits
        Write-Host -ForegroundColor Red "Failed to complete phase [$Phase], exiting...";
        Exit $ExitCode;
    }
}

function Local:Invoke-QuickExit {
    begin { Local:Enter-Scope -Invocation $MyInvocation; }
    end { Local:Exit-Scope -Invocation $MyInvocation; }

    process {
        Local:Remove-RunningFlag;

        Write-Host -ForegroundColor Red "Exiting...";
        Exit 0;
    }
}

#endregion - Exit Functions

function Invoke-Main {
    begin { Local:Enter-Scope -Invocation $MyInvocation; }
    end { Local:Exit-Scope -Invocation $MyInvocation; }

    process {
        Trap {
            Write-Host -ForegroundColor Red -Object "Unknown error occured, exiting...";
            Write-Host -ForegroundColor Red -Object $_;
            Local:Invoke-FailedExit -ExitCode 9999;
        }

        # Ensure only one process is running at a time.
        If (Local:Get-RunningFlag) {
            Write-Host -ForegroundColor Red "The script is already running in another session, exiting...";
            exit $Script:ALREADY_RUNNING;
        } else {
            Local:Set-RunningFlag;
        }

        try {
            Local:Invoke-EnsureLocalScript;
            Local:Invoke-EnsureNetworkSetup;
            Local:Invoke-EnsureModulesInstalled;
            $Local:InstallInfo = Local:Invoke-EnsureSetupInfo;
        } catch {
            Local:Invoke-FailedExit -ExitCode $Script:FAILED_SETUP_ENVIRONMENT;
        }

        Local:Invoke-ConfigureDeviceFromSetup -InstallInfo $Local:InstallInfo;
        # Queue this phase to run again if a restart is required by one of the environment setups.
        Local:Add-QueuedTask -QueuePhase $Phase -OnlyOnRebootRequired;

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
            Local:Invoke-QuickExit;
        }

        Local:Add-QueuedTask -QueuePhase $Local:NextPhase;
        Local:Invoke-QuickExit;
    }
}

Invoke-Main
