#Requires -Version 5.1
#Requires -RunAsAdministrator

Param (
    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [ValidateSet("Configure", "Cleanup", "Install", "Update")]
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

<#
.SYNOPSIS
    Logs the beginning of a function and starts a timer to measure the duration.
#>
function Enter-Scope([System.Management.Automation.InvocationInfo]$Invocation) {
    $Params = $Invocation.BoundParameters
    Write-Host "Entered scope $($Invocation.MyCommand.Name) with parameters [$($Params.Keys) = $($Params.Values)]"
}

<#
.SYNOPSIS
    Logs the end of a function and stops the timer to measure the duration.
#>
function Exit-Scope([System.Management.Automation.InvocationInfo]$Invocation) {
    Write-Host "Exited scope $($Invocation.MyCommand.Name)"
}

function With-Phase([String]$InnerPhase, [ScriptBlock]$ScriptBlock) {
    begin { Write-Host "Entering $InnerPhase phase..." }

    process {
        try {
            $ScriptBlock.Invoke()
        }
        catch {
            Write-Host "An error occurred during the $InnerPhase phase: $($_.Exception.Message)"
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

function Get-TaskTrigger {
    switch ($DryRun) {
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

function Set-StartupSchedule([String]$NextPhase, [switch]$Imediate) {
    begin { Enter-Scope $MyInvocation }

    process {
        $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -NoExit -File `"$($MyInvocation.PSCommandPath)`" -Phase $NextPhase -ScheduledTask -RecursionLevel $(if ($Phase -eq $NextPhase) { $RecursionLevel + 1 } else { 0 }) $(if ($DryRun) { "-DryRun" } else { " " })"
        $Task = New-ScheduledTask -Action $Action -Principal (Get-TaskPrincipal) -Settings (Get-TaskSettings) -Trigger (Get-TaskTrigger)

        Register-ScheduledTask -TaskName $TaskName -InputObject $Task
    }

    end { Exit-Scope $MyInvocation }
}

function Import-DownloadableModule([String]$Name) {
    begin { Enter-Scope $MyInvocation }

    process {
        $Module = Get-Module -ListAvailable | Where-Object { $_.Name -eq $Name }
        if ($null -eq $Module) {
            Write-Host "Downloading module $Name..."
            Install-Module -Name $Name -Scope CurrentUser -Confirm:$false -Force
            $Module = Get-Module -ListAvailable | Where-Object { $_.Name -eq $Name }
        }

        Import-Module $Module
    }

    end { Exit-Scope $MyInvocation }
}

# Section End - Utility Functions

function Configure {
    begin { Enter-Scope $MyInvocation }

    process {
        if (-not (Get-NetConnectionProfile -InterfaceAlias "Wi-Fi")) {
            Write-Host "No Wi-Fi connection found, creating profile..."

            $profilefile = "SetupWireless-profile.xml"

            $SSIDHEX = ($NetworkName.ToCharArray() | foreach-object { '{0:X}' -f ([int]$_) }) -join ''
            $XmlFile = "<?xml version=""1.0""?>
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
                Write-Host $XmlFile
            }
            else {
                Write-Host "Creating profile file $profilefile..."
                $XmlFile > ($profilefile)
                netsh wlan add profile filename="$($profilefile)"
                netsh wlan show profiles $NetworkName key=clear
                netsh wlan connect name=$NetworkName
            }

            Write-Host "Waiting for network connection..."
            while (-not (Test-Connection -ComputerName google.com -Count 1 -Quiet)) {
                Start-Sleep -Seconds 1
            }
            Write-Host "Connected to $NetworkName."
        }

        $DeviceName = $Script:InstallInfo.DeviceName
        if ($env:COMPUTERNAME -eq $DeviceName) {
            Write-Host "Device name is already set to $DeviceName."
        } else {
            Write-Host "Device name is not set to $DeviceName, setting it now..."
            Rename-Computer -NewName $DeviceName -WhatIf:$DryRun
            Set-RebootFlag
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

            # TODO - Check if the install info is still valid
            # TODO - If the install info is still valid, ask the user if they want to use it

            $InstallInfo
        } else {
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

        # # Check for winget and install it if it's not present
        # if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
        #     Write-Host "WinGet not found, installing..."

        #     # Sometimes this method can fail on brand new installs, if it does, we use a manual method
        #     try {
        #         Write-Host "Attempting to install WinGet using the Add-AppxPackage method..."
        #         Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
        #     } catch {
        #         Write-Host "Failed to install WinGet using the Add-AppxPackage method, trying manual method..."

        #         Write-Host "Downloading WinGet and its dependencies..."
        #         $Temp = Get-TempFolder "WinGet"
        #         $WingetInstaller = "$Temp/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        #         $VCLibs = "$Temp/Microsoft.VCLibs.x64.14.00.Desktop.appx"
        #         $Xaml = "$Temp/Microsoft.UI.Xaml.2.7.x64.appx"
        #         Invoke-RestMethod -Uri https://aka.ms/getwinget -OutFile $WingetInstaller
        #         Invoke-RestMethod -Uri https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx -OutFile $VCLibs
        #         Invoke-RestMethod -Uri https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.7.3/Microsoft.UI.Xaml.2.7.x64.appx -OutFile $Xaml

        #         Write-Host "Force stopping the HP Support Assistant if it's running..."
        #         Get-Process -Name myhp -ErrorAction SilentlyContinue | Stop-Process -Force

        #         Write-Host "Installing WinGet and its dependencies..."
        #         Add-AppxPackage $VCLibs
        #         Add-AppxPackage $Xaml
        #         Add-AppxPackage $WingetInstaller
        #     }
        # } else {
        #     Write-Host "WinGet found, skipping installation..."
        # }
    }

    end { Exit-Scope $MyInvocation }
}

function Install-Agent {
    begin { Enter-Scope $MyInvocation }

    process {
        $ErrorActionPreference = "Stop"

        # Download agent from N-Able
        Write-Information "Downloading agent..."

        $ClientId = $Script:InstallInfo.ClientId
        $SiteId = $Script:InstallInfo.SiteId
        $Uri = "https://system-monitor.com/api/?apikey=$ApiKey&service=get_site_installation_package&endcustomerid=$ClientId&siteid=$SiteId&os=windows&type=remote_worker"

        $Temp = Get-TempFolder "Agent"
        $OutputZip = "$Temp\agent.zip"
        $OutputFolder = "$Temp\unpacked"

        Write-Host "Downloading agent from [$Uri]..."
        Invoke-RestMethod -Uri $Uri -OutFile $OutputZip -UseBasicParsing -ErrorAction Stop
        Expand-Archive -Path $OutputZip -DestinationPath $OutputFolder -WhatIf:$DryRun -ErrorAction Stop
        $OutputExe = Get-ChildItem -Path $OutputFolder -Filter "*.exe" -File -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($null -eq $OutputExe) {
            Write-Error "Failed to find agent executable in [$OutputFolder]"
            Exit 1011
        }

        Write-Host "Installing agent from [$OutputExe]..."
        switch ($DryRun) {
            $true { Write-Host "Dry run enabled, skipping agent installation..." }
            $false { Start-Process -FilePath $OutputExe.FullName -Wait }
        }
    }
}

function Uninstall-HP {
    begin { Enter-Scope $MyInvocation }

    process {
        $HPPublisherId = "CN=ED344674-0FA1-4272-85CE-3187C9C86E26"
        Write-Information "Uninstalling HP bloatware..."

        # Removes myHP, HPAudioControl, HPSystemInformation, HPSupportAssistant, HPPrivacySettings, HPPowerManager, HPPCHardwareDiagnosticsWindows
        $Packages = Get-AppxPackage -AllUsers -Publisher $HPPublisherId
        Write-Host "Removing $($Packages.Count) HP bloatware packages..."
        $Packages | Remove-AppxPackage -WhatIf:$DryRun

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

        $WingetCmd = "winget uninstall --accept-source-agreements --disable-interactivity -e --purge --name"
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
                Write-Error $_
            }
        }

        $Command = '
        @("HP Security Update Service", "HP Wolf Security - Console") | ForEach-Object {
            $WingetCmd $_
        }

        Unregister-ScheduledTask -TaskName "HP Wolf Uninstall Reboot Persistence" -Confirm:$false
'

        $Trigger = New-ScheduledTaskTrigger -AtLogOn -User "$(whoami)"
        $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-Command { $Command }"
        $Principal = New-ScheduledTaskPrincipal -UserId "$(whoami)" -RunLevel Highest
        $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        $Task = New-ScheduledTask -Action $Action -Principal $Principal -Trigger $Trigger -Settings $Settings

        Register-ScheduledTask -TaskName "HP Wolf Uninstall Reboot Persistence" -InputObject $Task

        # return the function while running this last command in the background
        Write-Host "Removing HP Wolf Security using winget..."
        if ($DryRun) {
            Write-Host "Dry run enabled, skipping HP Wolf Security uninstallation..."
        } else {
            Start-Process -FilePath "powershell.exe" -ArgumentList "-Command { "$WingetCmd `"HP Wolf Security`"" }"
            Write-Host "HP Wolf Security is uninstalling, please wait for the uninstallation to complete..."
        }
    }

    end { Exit-Scope $MyInvocation }
}

function Main {
    begin { Enter-Scope $MyInvocation }

    process {
        $ErrorActionPreference = "Stop"
        Install-Requirements
        $Script:InstallInfo = Get-InstallInfo

        # if ($Script:InstallInfo.CompletedPhases -contains $Phase) {
        #     Write-Host "Skipping phase [$Phase] since it's already been completed..."
        #     Write-Host "If you want to re-run this phase, delete the file [$InstallInfoFile] and re-run this script."
        #     return
        # }

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

                    Write-Host "Setting up scheduled task [$TaskName] to run the next phase [Cleanup]..."
                    Set-StartupSchedule "cleanup" -Imediate
                }
                "cleanup" {
                    # TODO - Windows bullshit ads and other crap
                    Uninstall-HP

                    Write-Host "Setting up scheduled task [$TaskName] to run the next phase [Install]..."
                    Set-StartupSchedule "install" -Immediate
                }
                "install" {
                    if ($Script:InstallInfo.CompletedPhases -notcontains "configure") {
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

                    if (Get-Service -Name 'Advanced Monitoring Agent' -ErrorAction SilentlyContinue) {
                        Write-Host "Skipping phase [$Phase] since the agent is already installed..."
                    } else {
                        Install-Agent

                        while ($true) {
                            $AgentStatus = Get-Service -Name 'Advanced Monitoring Agent' -ErrorAction SilentlyContinue
                            if ($AgentStatus) {
                                Write-Host "The agent has been installed, current status is [$AgentStatus]..."
                                break
                            }

                            Write-Host "Waiting for the agent to be installed, current status is [$AgentStatus]..."
                            Start-Sleep -Seconds 5
                        }
                    }

                    Write-Host "Setting up scheduled task [$TaskName] to run the next phase [Update]..."
                    Set-StartupSchedule "update" -Immediate
                }
                "update" {
                    Import-DownloadableModule -Name PSWindowsUpdate -ErrorAction  Stop

                    # This will install all updates, rebooting if required, and start the process over again
                    Get-WindowsUpdate -Install -AcceptAll
                    Set-StartupSchedule $Phase
                    Restart-Computer -Force -WhatIf:$DryRun
                }
                "finish" {
                    # Ensure all phases are completed
                    # Remove any scheduled tasks
                    # Remove install info file
                    # Remove any files put in the temp folder
                    # Sign the localadmin out
                }
                default {
                    Write-Error "Unknown phase [$Phase]..."
                    exit 1000
                }
            }
        }
    }

    end { Exit-Scope $MyInvocation }
}

Main
