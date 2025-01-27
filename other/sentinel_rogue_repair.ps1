#Requires -RunAsAdministrator
#Requires -Version 5.1

Param(
    [String]$Account = "localadmin", # TODO: Should this be the current user?
    [String]$SentinelEndpoint = "apne1-swprd3.sentinelone.net",

    [String]$Password,

    [switch]$Repair,
    [switch]$DryRun
)

#region - Scope Functions

function Enter-Scope([System.Management.Automation.InvocationInfo]$Invocation) {
    $Params = $Invocation.BoundParameters
    Write-Host "Entered scope $($Invocation.MyCommand.Name) with parameters [$($Params.Keys) = $($Params.Values)]"
}

function Exit-Scope([System.Management.Automation.InvocationInfo]$Invocation) {
    Write-Host "Exited scope $($Invocation.MyCommand.Name)"
}

#endregion - Scope Functions

#region - Safe Mode Functions

function Enter-Safemode {
    begin { Enter-Scope $MyInvocation }

    process {
        Suspend-BitLocker -MountPoint "C:" -RebootCount 1 -WhatIf:$DryRun

        $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
        Set-ItemProperty $RegPath "AutoAdminLogon" -Value "1" -WhatIf:$DryRun
        Set-ItemProperty $RegPath "DefaultUsername" -Value "$Account" -WhatIf:$DryRun
        Set-ItemProperty $RegPath "DefaultPassword" -Value "$Password" -WhatIf:$DryRun

        Write-Host "Please reboot the computer into safemode to continue."
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

        Restart-Computer -Force -Confirm:$false -WhatIf:$DryRun
    }

    end { Exit-Scope $MyInvocation }
}

#endregion - Safe Mode Functions

#region - Steps

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

        # Ensure shortcut is run as administrator
        $bytes = [System.IO.File]::ReadAllBytes("$desktop\Please click me.lnk")
        $bytes[0x15] = $bytes[0x15] -bor 0x20 #set byte 21 (0x15) bit 6 (0x20) ON
        [System.IO.File]::WriteAllBytes("$desktop\Please click me.lnk", $bytes)
    }

    end { Exit-Scope $MyInvocation }
}

function Install-Requirements {
    begin { Enter-Scope $MyInvocation }

    process {
        if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
            Write-Host "Chocolatey installation not found, installing..."

            try {
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
                Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

                # Update the environment
                $env:ChocolateyInstall = Convert-Path "$((Get-Command choco).Path)\..\.."
                Import-Module "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
                Update-SessionEnvironment
            } catch {
                Write-Host "Chocolatey installation failed, exiting." -ForegroundColor Red
                Write-Host "Exception: $($_.Exception.GetType())" -ForegroundColor Red
                exit 1001
            }
        }

        if (!(Get-Command pwsh -ErrorAction SilentlyContinue)) {
            Write-Host "PowerShell Core installation not found, installing with chocolatey..."

            try {
                choco install powershell-core --no-progress --confirm
            } catch {
                Write-Host "PowerShell Core installation failed, exiting." -ForegroundColor Red
                Write-Host "Exception: $($_.Exception.GetType())" -ForegroundColor Red
                exit 1002
            }
        }
    }

    end { Exit-Scope $MyInvocation }
}

function Get-SentinelInstaller {
    begin { Enter-Scope $MyInvocation }

    process {
        $Installer = "$env:TEMP\sentinelone.exe"

        if (Test-Path -Path $Installer) {
            Write-Host "SentinelOne installer found at [$Installer], skipping download."
            return Get-Item -Path $Installer
        }

        # TODO: Get the latest installer from the API instead of hardcoding
        try {
            Write-Host "Downloading SentinelOne installer..."
            $Url = "https://nextcloud.racci.dev/s/nd7TsNG4FzTen9d/download/SentinelOneInstaller_windows_64bit_v23_1_4_650.exe"
            Invoke-WebRequest -Uri $Url -OutFile $Installer -UseBasicParsing -ErrorAction Stop
        } catch {
            Write-Host "Failed to download SentinelOne installer!" -ForegroundColor Red
            switch ($_.Exception.GetType()) {
                [System.Net.WebException] {
                    Write-Host "WebException: $($_.Exception.Message)" -ForegroundColor Red
                }
                default {
                    Write-Host "Exception: $($_.Exception.GetType())" -ForegroundColor Red
                }
            }
            exit 1004
        }

        Get-Item -Path $installer
    }

    end { Exit-Scope $MyInvocation }
}

function Invoke-Repair {
    begin { Enter-Scope $MyInvocation }

    process {
        $Installer = Get-SentinelInstaller

        if (!(Test-Path -Path $Installer)) {
            Write-Host "SentinelOne installer not found, exiting." -ForegroundColor Red
            exit 1003
        }

        Write-Host "Running SentinelOne Uninstaller, this may take a while..."
        $Process = Start-Process -FilePath $Installer -ArgumentList "-c -k 1 -t 1" -NoNewWindow -PassThru -WhatIf:$DryRun
        while ($Process.HasExited -eq $false) {
            Write-Host "Waiting for SentinelOne Uninstaller to finish..."
            Start-Sleep -Seconds 5
        }
        # Start-Process -FilePath $Installer -ArgumentList "-c -k 1 -t 1" -Wait -NoNewWindow -WhatIf:$DryRun

        Remove-Item -Path $Installer -WhatIf:$DryRun
        Remove-Item -Path "$([Environment]::GetFolderPath("CommonDesktopDirectory"))\Please Click Me.lnk" -WhatIf:$DryRun
    }

    end { Exit-Scope $MyInvocation }
}

#endregion - Steps

function Main {
    if ($Repair) {
        Invoke-Repair
        Exit-Safemode
    } else {
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
