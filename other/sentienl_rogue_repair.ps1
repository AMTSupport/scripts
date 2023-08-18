# Requires -RunAsAdministrator
#Requires -Version 5.1

Param(
    [String]$Account = "localadmin",
    [String]$SentinelEndpoint = "apne1-swprd3.sentinelone.net",

    [String]$SentinelApiKey,
    [String]$Password,

    [switch]$Repair,
    [switch]$DryRun
)

# Section Start - Utility Funtions

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

# Section End - Utility Funtions

# Section Start - Safe Mode Functions

function Enter-Safemode {
    begin { Enter-Scope $MyInvocation }

    process {
        $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
        Set-ItemProperty $RegPath "AutoAdminLogon" -Value "1" -WhatIf:$DryRun
        Set-ItemProperty $RegPath "DefaultUsername" -Value "$Account" -WhatIf:$DryRun
        Set-ItemProperty $RegPath "DefaultPassword" -Value "$Password" -WhatIf:$DryRun

        Start-Process -FilePath "bcdedit.exe" -ArgumentList "/set {default} safeboot minimal" -Wait -NoNewWindow -WhatIf:$DryRun
        Restart-Computer -Force -Confirm:$false -WhatIf:$DryRun
    }

    end { Exit-Scope $MyInvocation }
}

function Exit-Safemode {
    begin { Enter-Scope $MyInvocation }

    process {
        $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
        Set-ItemProperty -Path $RegPath -Name "AutoAdminLogon" -Value 0 -WhatIf:$DryRun
        Remove-ItemProperty -Path $RegPath -Name "DefaultUsername" -ErrorAction SilentlyContinue -WhatIf:$DryRun
        Remove-ItemProperty -Path $RegPath -Name "DefaultPassword" -ErrorAction SilentlyContinue -WhatIf:$DryRun

        Start-Process -FilePath "bcdedit.exe" -ArgumentList "/deletevalue {default} safeboot" -Wait -NoNewWindow -WhatIf:$DryRun
        Restart-Computer -Force -Confirm:$false -WhatIf:$DryRun
    }

    end { Exit-Scope $MyInvocation }
}

# Section End - Safe Mode Functions

# Section Start - Steps

function Add-DesktopRunner {
    begin { Enter-Scope $MyInvocation }

    process {
        $desktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
        $shortcut = "$desktop\Please click me.lnk"
        $wsh = New-Object -ComObject WScript.Shell
        $shortcut = $wsh.CreateShortcut($shortcut)
        $shortcut.TargetPath = "pwsh"
        $shortcut.Arguments = "-NoExit -NonInteractive -ExecutionPolicy Bypass -File `"$($MyInvocation.PSCommandPath)`" -Repair -DryRun:$DryRun"
        $shortcut.Save()
    }

    end { Exit-Scope $MyInvocation }
}

function Install-Requirements {
    begin { Enter-Scope $MyInvocation }

    process {
        if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
            Write-Host "Chocolatey installation not found, must install first."
            exit 1001
        }

        if (!(Get-Command pwsh -ErrorAction SilentlyContinue)) {
            Write-Host "PowerShell Core installation not found, installing with chocolatey..."

            choco install powershell-core --no-progress --confirm

            if (!(Get-Command pwsh -ErrorAction SilentlyContinue)) {
                Write-Host "PowerShell Core installation failed, exiting."
                exit 1002
            }
        }
    }

    end { Exit-Scope $MyInvocation }
}

function Get-SentinelInstaller {
    begin { Enter-Scope $MyInvocation }

    process {
        $installer = "C:\Windows\Temp\sentinelone.exe"

        if (Test-Path -Path $installer) {
            Write-Host "SentinelOne installer found, skipping download."
            return Get-Item -Path $installer
        }

        # TODO - Get the latest installer from the API instead of hardcoding
        $url = "https://${SentinelEndpoint}/web/api/v2.1/update/agent/download/1731852834663698166/1743420105324308764"
        Invoke-RestMethod -Uri $url -UseBasicParsing -OutFile $installer -Method Get -Headers @{
            Authorization = "ApiToken $SentinelApiKey"
        }

        Get-Item -Path $installer
    }

    end { Exit-Scope $MyInvocation }
}

function Run-Repair {
    begin { Enter-Scope $MyInvocation }

    process {
        $installer = Get-SentinelInstaller

        if (!(Test-Path -Path $installer)) {
            Write-Host "SentinelOne installer not found, exiting."
            exit 1003
        }

        Start-Process -FilePath $installer -ArgumentList "-c -t 1" -Wait -NoNewWindow -WhatIf:$DryRun
        Start-Process -FilePath $installer -ArgumentList "-c -k 1" -Wait -NoNewWindow -WhatIf:$DryRun

        Remove-Item -Path $installer -WhatIf:$DryRun
        Remove-Item -Path "$([Environment]::GetFolderPath("CommonDesktopDirectory"))\Please Click Me.lnk" -WhatIf:$DryRun
    }

    end { Exit-Scope $MyInvocation }
}

function Main {
    if ($Repair) {
        Run-Repair
        Exit-Safemode
    } else {
        if (!$SentinelApiKey) {
            Write-Host "SentinelOne API key not provided, exiting."
            exit 1000
        }

        if (!$Password) {
            Write-Host "Password not provided, exiting."
            exit 1000
        }

        Install-Requirements
        Get-SentinelInstaller
        Add-DesktopRunner
        Enter-Safemode
    }
}

Main
