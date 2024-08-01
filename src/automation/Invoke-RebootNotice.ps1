<#
.SYNOPSIS
    Determines if a reboot is required and sends a message to the user if it is.
.DESCRIPTION
    This script checks for a few conditions with their own reasons to determine if a reboot is required.
    If a reboot is required the user is sent a message with the reason and a request to reboot.

    The script will only send the message once per day at maximum, this is to avoid spamming the user with messages.

    The script will exit with an exit code of 5100 if a reboot is required,
    and with an exit code of 0 if no reboot is required.
.PARAMETER MaxUpTime
    The maximum amount of time the computer can be up before a reboot is required.
    The default is 7 days.
.INPUTS
    None
.OUTPUTS
    None
.EXAMPLE
    .\Invoke-RebootNotice.ps1
    This will check if a reboot is required and send a message to the user if it is.

    .\Invoke-RebootNotice.ps1 -MaxUpTime [TimeSpan]::FromDays(1)
    Runs the script with a maximum uptime of 1 day instead of the default 7.
#>

param(
    [TimeSpan]$MaxUpTime = [TimeSpan]::FromDays(7)
)

function Format-Time {
    param(
        [TimeSpan]$Time
    )

    if ($Time.TotalDays -gt 1) {
        return "$($Time.TotalDays) days"
    }

    if ($Time.TotalHours -gt 1) {
        return "$($Time.TotalHours) hours"
    }

    if ($Time.TotalMinutes -gt 1) {
        return "$($Time.TotalMinutes) minutes"
    }

    if ($Time.TotalSeconds -gt 1) {
        return "$($Time.TotalSeconds) seconds"
    }

    return 'less than a second'
}

function Get-ShouldRestart {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Restart; }

    process {
        if ((Get-CimInstance -Class Win32_OperatingSystem).LastBootUpTime -lt (Get-Date).Add(-$MaxUpTime)) {
            return [PSCustomObject]@{
                required = $true
                reason = "This computer hasn't been restarted for more than $(Format-Time $MaxUpTime)"
            }
        }

        if ($null -ne (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' -ErrorAction SilentlyContinue)) {
            return [PSCustomObject]@{
                required = $true
                reason   = 'This computer has pending updates that require a reboot.'
            }
        }


        return [PSCustomObject]@{
            required = $false
            reason   = 'No reboot required'
        }
    }
}

Import-Module $PSScriptRoot/../common/Environment.psm1;
Invoke-RunMain $PSCmdlet {
    $Local:RequiresRestart = Get-ShouldRestart;
    if (-not $Local:RequiresRestart.required) {
        Invoke-Info "No reboot required.";
        return;
    }

    # Only show the message once per day at maximum
    # Use a flag to track the last time the message was shown
    $Local:DisplayedMessage = Get-Flag 'REBOOT_HELPER_DISPLAYED';
    [Boolean]$Local:ShouldDisplayMessage = $True;
    if ($Local:DisplayedMessage.Exists()) {
        [String]$Local:RawLastDisplayed = $Local:DisplayedMessage.GetData();
        [DateTime]$Local:LastDisplayed = [DateTime]::Parse($Local:RawLastDisplayed);

        # If the message was displayed today, don't show it again
        # We also don't want to show the message if it was displayed within the hour and for example it was displayed at 23:59
        [Boolean]$Local:DisplayedToday = $Local:LastDisplayed.Date -eq (Get-Date).Date;
        [Boolean]$Local:DisplayedWithinHour = $Local:LastDisplayed -gt (Get-Date).AddHours(-1);

        if ($Local:DisplayedToday -and $Local:DisplayedWithinHour) {
            Invoke-Info "Reboot notice was already displayed today at $Local:LastDisplayed";
            $Local:ShouldDisplayMessage = $False;
        }
    }

    if ($Local:ShouldDisplayMessage) {
        try {
            $ErrorActionPreference = 'Stop';

            $Local:Message = @"
Message from AMT

$($Local:RequiresRestart.reason)
At your earliest convenience, please perform a restart.
"@;

            $Local:Message | . msg * /TIME:3600;

            if ($LASTEXITCODE -ne 0) {
                Invoke-Error "Failed to send reboot notice.";
            } else {
                Invoke-Info 'Reboot notice sent.';
                $Local:DisplayedMessage.Set((Get-Date));
            }
        } catch {
            Invoke-Error "Failed to send reboot notice: $_";
        }
    }

    Invoke-Error $Local:RequiresRestart.Reason;
    Invoke-FailedExit -ExitCode 5100;
};
