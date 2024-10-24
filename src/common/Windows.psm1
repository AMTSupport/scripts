<#
.SYNOPSIS
    Gets the last successful time synchronization time.

.OUTPUTS
    System.DateTime

    Returns the last successful time synchronization time, or the Unix epoch if the time could not be parsed.

.EXAMPLE
    Get-LastSyncTime

    Gets the last successful time synchronization time.
#>
function Get-LastSyncTime {
    [OutputType([DateTime])]
    param()

    process {
        $Regex = '^Last Successful Sync Time: (?<DateTime>[\d/:APM\s]+)$';
        $Result = w32tm /query /status | Select-String -Pattern $Regex;

        Try {
            $LastSyncTime = [DateTime]::Parse($Result.Matches[0].Groups['DateTime'].Value);
        } Catch {
            $LastSyncTime = Get-Date -Year 1970 -Month 1 -Day 1;
        }

        return $LastSyncTime;
    }
}

<#
.SYNOPSIS
    Syncs the system time with the default time server if the time is out of the supplied threshold.

.PARAMETER Threshold
    The time threshold to check against. Default is 7 days.

.OUTPUTS
    System.Boolean

    Returns $True if the system time was out of sync and was successfully synced, otherwise $False.

.EXAMPLE
    Sync-Time -Threshold (New-TimeSpan -Days 1)

    Syncs the system time if the time is out of sync by more than 1 day.

.EXAMPLE
    Sync-Time

    Syncs the system time if the time is out of sync by more than the default 7 days.
#>
function Sync-Time {
    [OutputType([System.Boolean])]
    param(
        [ValidateNotNullOrEmpty()]
        [timespan]$Threshold = (New-TimeSpan -Days 7)
    )

    process {
        [DateTime]$LastSyncTime = Get-LastSyncTime;
        [DateTime]$CurrentTime = Get-Date;

        if (($CurrentTime - $LastSyncTime) -gt $Threshold) {
            w32tm /resync /force;
            return $True;
        }

        return $False;
    }
}
