<#
.SYNOPSIS
    Determines if a reboot is required and sends a message to the user if it is.
.DESCRIPTION
    This script checks for a few conditions with their own reasons to determine if a reboot is required.
    If a reboot is required the user is sent a message with the reason and a request to reboot.

    The script will only display the message if the current time is within one of the time windows specified.
    This will be multiple times per day if there are more than one time window, but only once per time window.

    The script will exit with an exit code of 5100 if a reboot is required,
    and with an exit code of 0 if no reboot is required.
.PARAMETER MaxUpTime
    The maximum amount of time the computer can be up before a reboot is required.
    The default is 7 days.
.PARAMETER TimeWindows
    An array of time windows in which the message can be displayed.
    If this is set to null or an empty array the message will be displayed at any time.
    The default is 7-9, and 16-19.
    The format is an array of tuples with the first element being the start hour and the second element being the end hour.
    For example, [Tuple]::Create(7, 9) would be a time window from 7 to 9.
.PARAMETER AlwaysShow
    If this switch is set the message will be displayed even if it has already been shown for the time window or hour.
.INPUTS
    None
.OUTPUTS
    None
.EXAMPLE
    .\Invoke-RebootNotice.ps1
    This will check if a reboot is required and send a message to the user if it is.

    .\Invoke-RebootNotice.ps1 -MaxUpTime ([TimeSpan]::FromDays(1))
    Runs the script with a maximum uptime of 1 day instead of the default 7.

    .\Invoke-RebootNotice.ps1 -TimeWindows @([Tuple]::Create(7, 9), [Tuple]::Create(12, 14), [Tuple]::Create(16, 19))
    Runs the script with time windows from 7-9, 12-14, and 16-19.
#>

Using module ..\common\Environment.psm1
Using module ..\common\Logging.psm1
Using module ..\common\Scope.psm1
Using module ..\common\Flag.psm1
Using module ..\common\Exit.psm1

using namespace System.Collections.Generic

[CmdletBinding()]
param(
    [Parameter()]
    [TimeSpan]$MaxUpTime = [TimeSpan]::FromDays(7),

    [Parameter()]
    [Tuple[int,int][]]$TimeWindows = @(
        [Tuple]::Create(7, 9),
        [Tuple]::Create(16, 19)
    ),

    [Parameter()]
    [Switch]$AlwaysShow
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
                reason   = "This computer hasn't been restarted for more than $(Format-Time $MaxUpTime)"
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

Invoke-RunMain $PSCmdlet {
    $Local:RequiresRestart = Get-ShouldRestart;
    if (-not $Local:RequiresRestart.required) {
        Invoke-Info 'No reboot required.';
        return;
    }

    if ($null -eq $TimeWindows -or $TimeWindows.Count -eq 0) {
        Invoke-Debug 'No time windows specified, showing reboot notice at any time.';
        $Local:DateTimeWindows = @([Tuple]::Create([DateTime]::Now, [DateTime]::Now.AddHours(3)));
    } else {
        [Tuple[DateTime,DateTime][]]$Local:DateTimeWindows = $TimeWindows | ForEach-Object {
            [Tuple]::Create([DateTime]::Now.Date.AddHours($_.Item1), [DateTime]::Now.Date.AddHours($_.Item2))
        };
    };

    $Local:Now = Get-Date;
    $Local:WithinTimeWindow = $null;
    foreach ($Local:TimeWindow in $Local:DateTimeWindows) {
        Invoke-Debug "Checking time window: $Local:TimeWindow";
        if ($Local:TimeWindow.Item1 -le $Local:Now -and $Local:TimeWindow.Item2 -ge $Local:Now) {
            Invoke-Debug "Within time window: $Local:TimeWindow";
            $Local:WithinTimeWindow = $Local:TimeWindow;
            break;
        }
    }

    if ($null -eq $Local:WithinTimeWindow) {
        Invoke-Info 'Not within time window to show reboot notice.';
        return;
    }

    $Local:DisplayedMessage = Get-Flag "REBOOT_HELPER_DISPLAYED_$($Local:WithinTimeWindow.Item1.Hour)-$($Local:WithinTimeWindow.Item2.Hour)";
    Invoke-Debug "Last displayed at $($Local:DisplayedMessage.GetData())";
    [Boolean]$Local:ShouldDisplayMessage = $True;
    if (-not $AlwaysShow -and $Local:DisplayedMessage.Exists()) {
        [String]$Local:RawLastDisplayed = $Local:DisplayedMessage.GetData();
        [DateTime]$Local:LastDisplayed = [DateTime]::Parse($Local:RawLastDisplayed);

        # If the message was displayed today, don't show it again
        # We also don't want to show the message if it was displayed within the hour and for example it was displayed at 23:59
        [Boolean]$Local:DisplayedToday = $Local:LastDisplayed.Date -eq (Get-Date).Date;
        [Boolean]$Local:DisplayedWithinHour = $Local:LastDisplayed -gt (Get-Date).AddHours(-1);

        if ($Local:DisplayedToday -or $Local:DisplayedWithinHour) {
            Invoke-Info "Reboot notice was already displayed within the time window or hour, not showing again.";
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
            $Local:DisplayedMessage.Set((Get-Date));

            if ($LASTEXITCODE -ne 0) {
                Invoke-Error 'Failed to send reboot notice.';
            } else {
                Invoke-Info 'Reboot notice sent.';
            }
        } catch {
            Invoke-Error "Failed to send reboot notice: $_";
        }
    }

    $ExitCode = Register-ExitCode $Local:RequiresRestart.reason;
    exit $ExitCode;
};
