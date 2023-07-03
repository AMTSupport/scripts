#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.DESCRIPTION
    This script will check if a reboot is required from a windows auto-update or if the last boot time has exceeded the maximum allowed timeframe and schedule a reboot if required.
    When this task is triggered the user will receive a windows toast notification and a popup window notifying them of the pending reboot with it's reason.
    The script will create a Log file in the users temp directory with the reboot time and reason.
    This script is intended to be run as a scheduled task each day at a time when the computer is likely to be in use.

.NOTES
    This is currently broken and being worked on. Do not use.
#>

# Section start :: Set variables

$maxUpTime = 7 # Maximum uptime in days before reboot a required.

# The time of day which the reboot will occur. This is in 24 hour format.
# The default is 2am.
$rebootHour = 2

# Section end :: Set variables

# Section start :: Functions

function Init {
    process {
        Write-Host "Starting Restart Job."

        $Error.Clear()
    }
}

function Parse-Arguments ([Parameter()] [String[]]$Arguments) {
    process {
        if ($Arguments.Count -eq 0) {
            return
        }

        if ($Arguments -contains "-d" -or $Arguments -contains "--dry") {
            Write-Host "Dry run enabled. No changes will be made."
            $global:DryRun = $true
            return
        }

        $global:DryRun = $false
    }
}

function Get-DeviceName {
    process {
        $deviceName = (Get-CimInstance -Class Win32_ComputerSystem).Name
        Write-Host "Device name is $deviceName"
        return $deviceName
    }
}

function Get-UserName {
    process {
        $userName = (Get-CimInstance -Class Win32_ComputerSystem).UserName
        return $userName
    }
}

function ShouldRestart {
    process {
        if ($null -ne (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue)) {
            return [PSCustomObject]@{
                required = $true
                reason = "Windows Updates"
            }
        }

        if ((Get-CimInstance -Class Win32_OperatingSystem).LastBootUpTime -lt (Get-Date).AddDays(-$maxUpTime)) {
            return [PSCustomObject]@{
                required = $true
                reason = "Uptime exceeds maximum allowed of $maxUpTime days"
            }
        }

        return [PSCustomObject]@{
            required = $false
            reason = "No reboot required"
        }
    }
}

function PrepareVBS {
    process {
        $vbsPath = "C:\Temp\ps-run.vbs"
        if (Test-Path -Path $vbsPath) {
            Remove-Item -Path $vbsPath -Force
        }

        New-Item $vbsPath -ItemType File -Force

        Add-Content $vbsPath 'Set objShell = CreateObject("Wscript.Shell")'
        Add-Content $vbsPath 'Set args = Wscript.Arguments'
        Add-Content $vbsPath 'For Each arg In args'
        Add-Content $vbsPath '    objShell.Run("powershell -windowstyle hidden -executionpolicy bypass -noninteractive -Command " & arg & ""),0'
        Add-Content $vbsPath 'Next'

        return $vbsPath
    }
}

function NotifyUser (
    [Parameter(Mandatory = $true)]
    [DateTime]$rebootTime,
    [Parameter(Mandatory = $true)]
    [String]$rebootReason
) {
    process {
        $formatedRebootTime = $rebootTime.ToString("HH:mm")
        $rebootDate = $rebootTime.ToString("dd/MM/yyyy")
        $rebootMessage = "Your computer will restart at $formatedRebootTime on $rebootDate. Please save your work and close all applications. This is due to: $rebootReason"

        $inlineScript = @"
[reflection.assembly]::LoadWithPartialName('System.Windows.Forms') | Out-Null;
[reflection.assembly]::LoadWithPartialName('System.Drawing') | Out-Null;
`$toast = [System.Windows.Forms.NotifyIcon]::new();
`$toast.icon = [System.Drawing.SystemIcons]::Information;
`$toast.visible = `$true;
`$toast.showballoontip(10000, 'Reboot Scheduled', '$rebootMessage', [System.Windows.Forms.ToolTipIcon]::None);
[System.Windows.Forms.MessageBox]::Show('$rebootMessage', 'Reboot Scheduled', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
"@

        $action = New-ScheduledTaskAction -Execute wscript.exe -Argument "`"C:\Temp\ps-run.vbs`" `"& { $inlineScript }`""
        $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date) + (New-TimeSpan -Seconds 5))
        $principal = New-ScheduledTaskPrincipal -UserID (Get-UserName) -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances Parallel

        Register-ScheduledTask -TaskName "UserNotifyTask" -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force
    }
}

function CreateLog (
    [Parameter(Mandatory = $true)]
    [DateTime]$rebootTime,
    [Parameter(Mandatory = $true)]
    [String]$rebootReason
) {
    process {
        $rebootLog = "$env:TEMP\RebootLog.txt"
        $rebootLogContent = @"
    Reboot scheduled for $rebootTime

    Reboot reason: $rebootReason
"@

        Write-Host "Creating reboot log at $rebootLog"
        $rebootLogContent | Out-File -FilePath $rebootLog -Force
    }
}

function Finalise {
    process {
        Write-Host "Finished Restart Job."

        $global:DryRun = $null
        $Error.Clear()
    }
}

# Section end :: Functions

Init
Parse-Arguments -Arguments $args
$restart = (ShouldRestart)
$rebootTime = (Get-Date).AddDays(1).Date.AddHours($rebootHour)

if ($restart.required) {
    GetTask $rebootTime
    PrepareVBS
    NotifyUser $rebootTime $restart.reason
    CreateLog $rebootTime $restart.reason
} else {
    Write-Host "No reboot required"
}

Finalise
