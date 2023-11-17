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
    [switch]$NoSchedule,

    [Parameter()]
    [ValidateSet("Configure", "Cleanup", "Install", "Update", "Finish")]
    [String]$Phase = "Configure",

    [Parameter()]
    [ValidateLength(32, 32)]
    [String]$ApiKey = "",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]$Endpoint = "system-monitor.com",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]$NetworkName = "Guests",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]$NetworkPassword = "",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]$TaskName = "SetupScheduledTask",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [switch]$ScheduledTask,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [Int]$RecursionLevel = 0
)

# Section Start - Utility Functions

#region - Error Codes

$Script:NULL_ARGUMENT = 1000
$Script:FAILED_TO_LOG = 1001
$Script:FAILED_TO_CONNECT = 1002
$Script:ALREADY_RUNNING = 1003

#endregion - Error Codes

#region - Utility Functions

function Local:Assert-NotNull([Parameter(Mandatory, ValueFromPipeline)][Object]$Object, [String]$Message) {
    if ($null -eq $Object -or $Object -eq "") {
        if ($null -eq $Message) {
            Write-Error "Object is null" -Category InvalidArgument
        }
        else {
            Write-Error $Message -Category InvalidArgument
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

#endregion - Utility Functions

function With-Phase([String]$InnerPhase, [ScriptBlock]$ScriptBlock) {
    begin { Write-Host "Entering $InnerPhase phase..." }

    process {
        try {
            & $ScriptBlock
        }
        catch {
            Write-Host "An error occurred during the $InnerPhase phase: $($_.Exception.Message)"
            Write-Host -ForegroundColor Red $_.Exception.StackTrace
            exit 1001
        }

        $NewInstallInfo = $Script:InstallInfo
        [String[]]$CompletedPhases = $Script:InstallInfo.CompletedPhases
        if ($null -eq $CompletedPhases) { $CompletedPhases = @($InnerPhase) } else { $CompletedPhases += $InnerPhase }
        $NewInstallInfo.CompletedPhases = $CompletedPhases

        $Script:InstallInfo = $NewInstallInfo
        $Script:InstallInfo | ConvertTo-Json | Out-File -FilePath $Script:InstallInfo.Path -Encoding UTF8 -Force
    }

    end { Write-Host "Finished $InnerPhase phase successfully." }
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

function Get-TempFolder([String]$Sub) {
    begin { Enter-Scope $MyInvocation }

    process {
        $TempFolder = "$($env:TEMP)\$Sub"
        if (-not (Test-Path $TempFolder)) {
            Write-Host "Creating temporary folder $TempFolder..."
            New-Item -ItemType Directory -Path $TempFolder
        }

        $TempFolder
    }

    end { Exit-Scope $MyInvocation }
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

# Configure items like device name from the setup the user provided.
function Local:Invoke-ConfigureDeviceFromSetup([Parameter(Mandatory)][ValidateNotNullOrEmpty()][PSCustomObject]$InstallInfo) {
    begin { Local:Enter-Scope -Invocation $MyInvocation }
    end { Local:Exit-Scope -Invocation $MyInvocation }

    process {
        $InstallInfo | Local:Assert-NotNull "Install info was null";

        #region - Device Name
        [String]$Local:DeviceName = $InstallInfo.DeviceName;
        $Local:DeviceName | Local:Assert-NotNull "Device name was null";

        [String]$Local:ExistingName = $env:COMPUTERNAME;
        $Local:ExistingName | Local:Assert-NotNull "Existing name was null"; # TODO :: Alternative method of getting existing name if $env:COMPUTERNAME is null

        if ($Local:ExistingName -eq $Local:DeviceName) {
            Write-Host "Device name is already set to $Local:DeviceName.";
        }
        else {
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
        }
        catch {
            Write-Error "Failed to set auto-login registry keys";
        }
    }
}

# Make sure all required modules have been installed.
function Local:Invoke-EnsureModulesInstalled {
    begin { Local:Enter-Scope -Invocation $MyInvocation }
    end { Local:Exit-Scope -Invocation $MyInvocation }

    process {
        Import-DownloadableModule -Name WingetTools
        Import-DownloadableModule -Name PSWindowsUpdate

        if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Host "WinGet not found, installing..."
            Install-Winget
        }
    }
}

#endregion -- Environment Setup

#region - Steps

function Install-Agent {
    begin { Enter-Scope $MyInvocation }

    process {
        $ErrorActionPreference = "Stop"

        # Check if the agent is already installed
        if ((-not $DryRun) -and (Get-Service -Name "Advanced Monitoring Agent" -ErrorAction SilentlyContinue)) {
            Write-Host "Agent is already installed, skipping installation..."
            return
        }

        # Download agent from N-Able
        Write-Information "Downloading agent..."

        $ClientId = $Script:InstallInfo.ClientId
        $SiteId = $Script:InstallInfo.SiteId
        $Uri = "https://system-monitor.com/api/?apikey=$ApiKey&service=get_site_installation_package&endcustomerid=$ClientId&siteid=$SiteId&os=windows&type=remote_worker"

        $Temp = "$env:TEMP\Agent"
        if (-not (Test-Path $Temp)) {
            Write-Host "Creating temporary folder $Temp..."
            New-Item -ItemType Directory -Path $Temp | Out-Null
        }

        $OutputZip = "$Temp\agent.zip"
        $OutputFolder = "$Temp\unpacked"

        Write-Host "Downloading agent from [$Uri]..."
        Invoke-WebRequest -Uri $Uri -OutFile $OutputZip -UseBasicParsing -ErrorAction Stop
        Expand-Archive -Path $OutputZip -DestinationPath $OutputFolder -ErrorAction Stop

        $Output = Get-ChildItem -Path $OutputFolder -Filter "*.exe" -File -ErrorAction Stop

        # For some reason theres an issue with the path being an array
        # When being downloaded within the same session, but not within the function
        # Only once the function is returned does the value become an array.
        # This seems to be a bug with powershell, but I'm not sure.
        $OutputExe
        foreach ($subpath in $Output) {
            Write-Host $subpath
            $OutputExe = $subpath
        }

        if ($null -eq $OutputExe) {
            Write-Host "Failed to find agent executable in [$OutputFolder]"
            Exit 1011
        }

        Write-Host "Installing agent from [$OutputExe]..."
        switch ($DryRun) {
            $true { Write-Host "Dry run enabled, skipping agent installation..." }
            $false { Start-Process -FilePath $OutputExe.FullName -Wait }
        }

        while ($true) {
            $AgentStatus = Get-Service -Name 'Advanced Monitoring Agent' -ErrorAction SilentlyContinue
            if ($AgentStatus -and $AgentStatus.Status -eq "Running") {
                Write-Host "The agent has been installed and running, current status is [$AgentStatus]..."
                break
            }

            Write-Host "Waiting for the agent to be installed and running, current status is [$AgentStatus]..."
            Start-Sleep -Seconds 5
        }

        # TODO - Query if sentinel is configured, if so wait for sentinel and the agent to be running services, then restart the computer
    }
}

function Uninstall-HP {
    begin { Enter-Scope $MyInvocation }

    process {
        $WingetCmd = "winget uninstall --accept-source-agreements --disable-interactivity -e --purge --name"

        if ($RecursionLevel -eq 1) {
            Write-Host "Uninstalling remaining HP Security Wolf Components..."
            Invoke-Expression "$WingetCmd `"HP Wolf Security - Console`""
            Invoke-Expression "$WingetCmd `"HP Security Update Service`""

            return
        }

        $HPPublisherId = "CN=ED346674-0FA1-4272-85CE-3187C9C86E26"
        Write-Information "Uninstalling HP bloatware..."

        # Removes myHP, HPAudioControl, HPSystemInformation, HPSupportAssistant, HPPrivacySettings, HPPowerManager, HPPCHardwareDiagnosticsWindows
        $Packages = Get-AppxPackage -AllUsers -Publisher $HPPublisherId
        Write-Host "Removing $($Packages.Count) HP bloatware packages..."
        $Packages | Remove-AppxPackage -WhatIf:$DryRun # TODO: Can i use the -AllUsers flag heres?

        # HP Documentation           HP_Documentation                                      1.0.0.1
        # HP Sure Recover { 052C94ED-06A6-4B48-ABAE-56D796EE7107 }                10.1.12.38
        # HP Wolf Security - Console { 1B8CBE4F-A015-431D-B0B6-A8E33FD1C6CF }                11.0.19.378
        # HP Wolf Security { 6F14D6F0-7663-11ED-9748-10604B96B11C }                4.4.2.1075
        # HP Sure Run Module { 83C5C3DC-E060-491C-A071-FA36E29315A5 }                5.0.3.29
        # HP Wolf Security { EC86888F-C7F8-11ED-AA30-3863BB3CB5AC }                4.4.2.2945
        # HP Security Update Service { ECBD9C21-3CC3-41C2-BA81-FE17685C0205 }                4.4.2.2848
        # HP Connection Optimizer { 6468C4A5-E47E-405F-B675-A70A70983EA6 }                2.0.19.0
        # HP Notifications { 84937F28-9CB4-49E7-A2CF-E32D97E6DAE6 }                1.1.28.1
        # HP Audio Control           RealtekSemiconductorCorp.HPAudioControl_dt26b99r8h8gj 2.41.289.0

        $WingetUninstalls = @(
            "HP Documentation",
            "HP Sure Recover",
            "HP Sure Run Module",
            "HP Connection Optimizer",
            "HP Notifications",
            "HP Audio Control"
        )

        Write-Host "Removing $($WingetUninstalls.Count) HP bloatware packages using winget..."
        foreach ($PackageId in $WingetUninstalls) {
            try {
                If ($DryRun) {
                    Write-Host "Dry run enabled, skipping winget uninstall of [$PackageId]..."
                    Write-Host "Would have run [$WingetCmd `"$PackageId`"]"
                    continue
                }

                Invoke-Expression "$WingetCmd `"$PackageId`""
            }
            catch {
                Write-Warning "Failed to uninstall package [$PackageId] using winget..."
                Write-Host -ForegroundColor Red $_
            }
        }

        # TODO - If already uninstall-don't schedule and run next phase instead of re-running this phase after reboot which won't be called
        # Return the function while running this last command in the background
        Write-Host "Removing HP Wolf Security using winget..."
        if ($DryRun) {
            Write-Host "Dry run enabled, skipping HP Wolf Security uninstallation..."
        } else {
            Start-Process -FilePath "powershell.exe" -ArgumentList '-NoExit -Command "& { winget uninstall -e --purge --name `""HP Wolf Security`"" }"'
            Write-Host "HP Wolf Security is uninstalling, please wait for the uninstallation to complete..."
        }
    }

    end { Exit-Scope $MyInvocation }
}

function Update-Windows {
    # After 3 reboots we procced to the finish phase
    if ($RecursionLevel -ge 3) {
        Set-StartupSchedule "finish" -Imediate
    }

    # This will install all updates, rebooting if required, and start the process over again
    Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot -WhatIf:$DryRun
    Set-StartupSchedule $Phase
    Restart-Computer -Force -WhatIf:$DryRun
}

#regionend - Steps

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

function Local:Set-Flag([Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$Context) {
    begin { Enter-Scope -Invocation $MyInvocation }
    end { Exit-Scope -Invocation $MyInvocation }

    process {
        $Context | Local:Assert-NotNull "Context was null";

        [String]$Flag = Local:Get-FlagPath -Context $Context;
        New-Item -ItemType File -Path $Flag -Force;
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

function Local:Remove-Flag([Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$Context) {
    begin { Enter-Scope -Invocation $MyInvocation }
    end { Exit-Scope -Invocation $MyInvocation }

    process {
        $Context | Local:Assert-NotNull "Context was null";

        [String]$Local:Flag = Local:Get-FlagPath -Context $Context;
        Remove-Item -Path $Local:Flag -Force -ErrorAction SilentlyContinue
    }
}

function Set-RebootFlag { Local:Set-Flag -Context "reboot" }
function Remove-RebootFlag { Local:Remove-Flag -Context "reboot" }
function Get-RebootFlag { Local:Get-Flag -Context "reboot" }
#endregion - Flag Settings

#region - Task Scheduler Implementation
function Local:Set-StartupSchedule([String]$NextPhase, [switch]$Imediate, [String]$CommandPath = $MyInvocation.PSCommandPath) {
    begin { Enter-Scope -Invocation $MyInvocation }
    end { Exit-Scope -Invocation $MyInvocation }

    process {
        if ($NoSchedule) {
            return
        }

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
            -Argument "-ExecutionPolicy Bypass -NoExit -File `"$CommandPath`" -Phase $NextPhase -ScheduledTask -RecursionLevel $Local:RecursionLevel $(if ($DryRun) { "-DryRun" } else { " " })";

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
    begin { Enter-Scope $MyInvocation }
    end { Exit-Scope $MyInvocation }

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

                Remove-RebootFlag;
                Restart-Computer -Force -WhatIf:$DryRun;
            } else {
                # Add flag about missing reboot
            }
        }
    }
}

#endregion - Queue Functions

function Local:Invoke-FailedExit {
    begin { Enter-Scope $MyInvocation }
    end { Exit-Scope $MyInvocation }

    process {
        Local:Remove-QueuedTask;
        Local:Remove-Flag -Context "running";

        Write-Host "Failed to complete phase [$Phase], exiting...";
    }
}

function Main {
    begin { Local:Enter-Scope -Invocation $MyInvocation }
    end { Local:Exit-Scope -Invocation $MyInvocation }

    process {
        $ErrorActionPreference = "Stop"

        # Remove the task that possibly started this.
        Local:Remove-QueuedTask;

        If (Local:Get-Flag -Context "running") {
            Write-Host "The script is already running, exiting...";
            exit $Script:ALREADY_RUNNING;
        } else {
            Local:Set-Flag -Context "running";
        }

        try {
            Local:Invoke-EnsureLocalScript;
            Local:Invoke-EnsureNetworkSetup;
            Local:Invoke-EnsureModulesInstalled;
            $Local:InstallInfo = Local:Invoke-EnsureSetupInfo;
        } catch {
            Local:Remove-Flag -Context "running";
            Write-Error "Failed to setup environment";
        }

        Local:Invoke-ConfigureDeviceFromSetup -InstallInfo $Local:InstallInfo;
        # Queue this phase to run again if a restart is required by one of the environment setups.
        Local:Add-QueuedTask -QueuePhase $Phase -OnlyOnRebootRequired;


        switch ($Phase) {
            "configure" { Invoke-PhaseConfigure -InstallInfo $Local:InstallInfo }
            "cleanup" { Invoke-PhaseCleanup -InstallInfo $Local:InstallInfo }
            "install" { Invoke-PhaseInstall -InstallInfo $Local:InstallInfo }
            "update" { Invoke-PhaseUpdate -InstallInfo $Local:InstallInfo }
            "finish" { Invoke-PhaseFinish -InstallInfo $Local:InstallInfo }
        }

        Local:Add-QueuedTask -QueuePhase "finish";
        Local:Remove-Flag -Context "running";

        With-Phase $Phase {
            switch ($Phase) {
                "configure" {
                    Configure

                    Set-StartupSchedule "cleanup" -Imediate
                }
                "cleanup" {
                    # TODO - Windows bullshit ads and other crap
                    Uninstall-HP

                    switch ($RecursionLevel) {
                        0 { Set-StartupSchedule $Phase -Imediate:$DryRun }
                        1 { Set-StartupSchedule "Install" -Imediate }
                        _ { Write-Host "Recursion level [$RecursionLevel] is too high, aborting..." -ForegroundColor Red; exit 1005 }
                    }
                }
                # If already installed, run next phase immediatly
                "install" {
                    if ((-not $DryRun) -and $Script:InstallInfo.CompletedPhases -notcontains "configure") {
                        Write-Host "Skipping phase [$Phase] since the configure phase hasn't been completed yet..."
                        exit 1002
                    }

                    if (Get-RebootFlag) {
                        Write-Host "The device requires a reboot before the install phase can be completed, rebooting now..."
                        # TODO - Add a scheduled task to run this script again after reboot
                        If ($DryRun) {
                            Write-Host "Dry run enabled, skipping reboot..."
                        } else {
                            Set-StartupSchedule $Phase -Imediate:$DryRun
                            Restart-Computer -Force -WhatIf:$DryRun
                        }
                        exit 1003
                    }

                    Install-Agent
                    Set-StartupSchedule "update" -Imediate
                }
                "update" {
                    Import-DownloadableModule -Name PSWindowsUpdate -ErrorAction Stop

                    Update-Windows
                }
                "finish" {
                    Write-Host "Finished all phases, removing scheduled task [$TaskName]..."
                    Unregister-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue -Confirm:$false

                    Write-Host "Removing temporary files..."
                    Remove-Item -Path "$env:TEMP\*" -Force -Recurse -Exclude "InstallInfo.json"

                    Write-Host "Finished all phases successfully."
                    exit 0 # Exit early since we will have an error with the completed phases check
                }
                default {
                    Write-Host -ForegroundColor Red "Unknown phase [$Phase]..."
                    exit 1000
                }
            }
        }
    }
}

Main
