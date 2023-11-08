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

#region - Scope Functions

function Enter-Scope([System.Management.Automation.InvocationInfo]$Invocation) {
    $Params = $Invocation.BoundParameters
    Write-Host "Entered scope $($Invocation.MyCommand.Name) with parameters [$($Params.Keys) = $($Params.Values)]"
}

function Exit-Scope([System.Management.Automation.InvocationInfo]$Invocation) {
    Write-Host "Exited scope $($Invocation.MyCommand.Name)"
}

#endregion - Scope Functions

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

function Set-Flag([String]$Context) {
    begin { Enter-Scope $MyInvocation }

    process {
        $Flag = "$($env:TEMP)\$Context.flag"
        New-Item -ItemType File -Path $Flag -Force
    }

    end { Exit-Scope $MyInvocation }
}

function Get-Flag([String]$Context) {
    begin { Enter-Scope $MyInvocation }

    process {
        $Flag = "$($env:TEMP)\$Context.flag"
        Test-Path $Flag
    }

    end { Exit-Scope $MyInvocation }
}

function Remove-Flag([String]$Context) {
    begin { Enter-Scope $MyInvocation }

    process {
        $Flag = "$($env:TEMP)\$Context.flag"
        Remove-Item -Path $Flag -Force -ErrorAction SilentlyContinue
    }

    end { Exit-Scope $MyInvocation }
}

function Set-RebootFlag { Set-Flag -Context "reboot" }
function Remove-RebootFlag { Remove-Flag -Context "reboot" }
function Get-RebootFlag { Get-Flag -Context "reboot" }

function Get-TaskTrigger([switch]$Imediate) {
    switch ($Imediate) {
        $true { $Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5) }
        $false { $Trigger = New-ScheduledTaskTrigger -AtLogOn -User "$(whoami)" }
    }

    $Trigger
}

function Get-TaskSettings {
    New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -WakeToRun
}

function Get-TaskPrincipal {
    New-ScheduledTaskPrincipal -UserId "$(whoami)" -RunLevel Highest
}

function Set-StartupSchedule([String]$NextPhase, [switch]$Imediate, [String]$CommandPath = $MyInvocation.PSCommandPath) {
    begin { Enter-Scope $MyInvocation }

    process {
        if ($NoSchedule) {
            return
        }

        $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -NoExit -File `"$CommandPath`" -Phase $NextPhase -ScheduledTask -RecursionLevel $(if ($Phase -eq $NextPhase) { $RecursionLevel + 1 } else { 0 }) $(if ($DryRun) { "-DryRun" } else { " " })"
        $Task = New-ScheduledTask -Action $Action -Principal (Get-TaskPrincipal) -Settings (Get-TaskSettings) -Trigger (Get-TaskTrigger -Imediate:$Imediate)

        Register-ScheduledTask -TaskName $TaskName -InputObject $Task -ErrorAction Stop | Out-Null
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

# Section End - Utility Functions

function Get-Network {
    begin { Enter-Scope $MyInvocation }

    process {
        if (-not ((Get-NetConnectionProfile -InterfaceAlias "Wi-Fi" -ErrorAction SilentlyContinue) -or (Get-NetConnectionProfile -InterfaceAlias "WiFi" -ErrorAction SilentlyContinue))) {
            Write-Host "No Wi-Fi connection found, creating profile..."

            $profilefile = "$env:TEMP\SetupWireless-profile.xml"

            $SSIDHEX = ($NetworkName.ToCharArray() | foreach-object { '{0:X}' -f ([int]$_) }) -join ''
            $XmlContent = "<?xml version=""1.0""?>
<WLANProfile xmlns=""http://www.microsoft.com/networking/WLAN/profile/v1"">
    <name>$NetworkName</name>
    <SSIDConfig>
        <SSID>
            <hex>$SSIDHEX</hex>
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
                Write-Host "Would have created profile file $profilefile with contents:"
                Write-Host $XmlContent
            }
            else {
                Write-Host "Creating profile file $profilefile..."
                $XmlContent > ($profilefile)
                netsh wlan add profile filename="$($profilefile)" | Out-Null
                netsh wlan show profiles $NetworkName key=clear | Out-Null
                netsh wlan connect name=$NetworkName | Out-Null
            }

            Write-Host "Waiting for network connection..."
            while (-not (Test-Connection -ComputerName google.com -Count 1 -Quiet)) {
                Start-Sleep -Seconds 1
            }
            Write-Host "Connected to $NetworkName."
        }
    }

    end { Exit-Scope $MyInvocation }
}

function Configure {
    begin { Enter-Scope $MyInvocation }

    process {
        $DeviceName = $Script:InstallInfo.DeviceName
        if ($env:COMPUTERNAME -eq $DeviceName) {
            Write-Host "Device name is already set to $DeviceName."
        } else {
            Write-Host "Device name is not set to $DeviceName, setting it now..."
            Rename-Computer -NewName $DeviceName -WhatIf:$DryRun
            Set-RebootFlag
        }

        $AutoLogin = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon" -ErrorAction SilentlyContinue
        if ($null -eq $AutoLogin) {
            Write-Host "Auto login is not enabled, enabling it now..."
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon" -Value 1 -ErrorAction Stop
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultUserName" -Value "localadmin" -ErrorAction Stop
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultPassword" -Value "" -ErrorAction Stop
        } else {
            Write-Host "Auto login is already enabled, skipping..."
        }
    }

    end { Exit-Scope $MyInvocation }
}

function Get-InstallInfo {
    begin { Enter-Scope $MyInvocation }

    process {
        $File = "$($env:TEMP)\InstallInfo.json"
        if (Test-Path $File) {
            Write-Host "Reading install info from $File..."
            $InstallInfo = Get-Content -Path $File -Raw | ConvertFrom-Json

            Write-Host "Install info:"
            Write-Host $InstallInfo

            $InstallInfo
        } else {
            Write-Host "No install info found, creating new install info..."

            $Clients = (Get-SoapResponse -Uri (Get-BaseUrl "list_clients")).items.client
            $FormattedClients = Get-FormattedName2Id -InputArr $Clients -IdExpr { $_.clientid }
            $SelectedClient = $FormattedClients | Out-GridView -Title "Select a client" -PassThru

            $Sites = (Get-SoapResponse -Uri "$(Get-BaseUrl "list_sites")&clientid=$($SelectedClient.Id)").items.site
            $FormattedSites = Get-FormattedName2Id -InputArr $Sites -IdExpr { $_.siteid }
            $SelectedSite = $FormattedSites | Out-GridView -Title "Select a site" -PassThru

            # TODO - Show a list of devices for the selected client so the user can confirm they're using the correct naming convention
            $DeviceName = Get-PromptInput -title "Device Name" -question "Enter a name for this device"

            $InstallInfo = @{
                "DeviceName" = $DeviceName
                "ClientId"   = $SelectedClient.Id
                "SiteId"     = $SelectedSite.Id
                "Path"       = $File
            }

            Write-Host "Saving install info to $File..."
            $InstallInfo | ConvertTo-Json | Out-File -FilePath $File

            Write-Host "Install info:"
            Write-Host $InstallInfo

            $InstallInfo
        }
    }

    end { Exit-Scope $MyInvocation }
}

function Install-Requirements {
    begin { Enter-Scope $MyInvocation }

    process {
        Import-DownloadableModule -Name WingetTools

        if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Host "WinGet not found, installing..."
            Install-Winget
        }
    }

    end { Exit-Scope $MyInvocation }
}

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

function Main {
    begin { Enter-Scope $MyInvocation }

    process {
        $ErrorActionPreference = "Stop"

        if ($MyInvocation.PSScriptRoot -ne ((Get-Item $env:TEMP).FullName)) {
            Write-Host "Copying script to temp folder..."
            $Into = "$env:TEMP\win_setup.ps1"
            Copy-Item -Path $MyInvocation.PSCommandPath -Destination $Into -Force
            Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -NoExit -File `"$Into`" -Phase $Phase -RecursionLevel $RecursionLevel"
            return
        }

        Get-Network
        Install-Requirements
        $Script:InstallInfo = Get-InstallInfo

        # Removes the scheduled task if it exists
        if ($ScheduledTask) {
            Write-Host "Removing scheduled task [$TaskName]..."
            Remove-RebootFlag
            Unregister-ScheduledTask -TaskName $TaskName -ErrorAction Stop -Confirm:$false
        }

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

    end { Exit-Scope $MyInvocation }
}

Main
