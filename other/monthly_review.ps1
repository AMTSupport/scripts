Param(
    [Parameter(Mandatory)]
    [String]$ClientName,

    [Parameter(DontShow)]
    [String]$SharedFolder = ($MyInvocation.MyCommand.PSScriptRoot | Split-Path -Parent | Split-Path -Parent) # Maybe just get the folder after the username?
)

#region - Error Codes

$Script:NULL_ARGUMENT = 1000
$Script:FAILED_TO_LOG = 1001

#endregion - Error Codes

#region - Utility Functions

function Local:Assert-NotNull([Parameter(Mandatory, ValueFromPipeline)][Object]$Object, [String]$Message) {
    if ($null -eq $Object) {
        if ($null -eq $Message) {
            Write-Error "Object is null" -Category InvalidArgument
        }
        else {
            Write-Error $Message -Category InvalidArgument
        }

        exit $NULL_ARGUMENT
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

function Local:Invoke-Script([Parameter(Mandatory)][String]$ScriptName, [Parameter(ValueFromPipeline)][PSCustomObject]$Params) {
    [String]$Script = "$($MyInvocation.PSScriptRoot)/$Name.ps1";


    if (-not (Test-Path $Script)) {
        Write-Host "Script not found: $Script"
        Exit 1001
    }

    Write-Host "Running $Script with params $Params"
    & $Script @Params
}

#endregion - Utility Functions

#region - File Helpers

<#
.SYNOPSIS
Ensures that a file at the given path exists.

.DESCRIPTION
Ensures that a file at the given path exists.
If the file does not exist an ObjectNotFound error is thrown.
If the file is a folder an InvalidArgument error is thrown.

.PARAMETER Path
The path to the file to check, must not be null or empty.
#>
function Local:Assert-FileExists([Parameter(Mandatory, ValueFromPipeline)][ValidateNotNullOrEmpty()][String]$Path) {
    if (-not (Test-Path $Path)) {
        Write-Error "File not found: $Path" -Category ObjectNotFound
    }


}

function Local:Assert-FolderExists {

}

#endregion - File Helpers

#region - Tasks/Steps

function Get-SecurityScoreReport {
    begin { Local:Enter-Scope -Invocation $MyInvocation; }
    end { Local:Exit-Scope -Invocation $MyInvocation; }

    process {
        # Filtering only identity and apps, not device or data.

        # Get current Security Score from O365 Dashboard
        # Get Security Score from 29 days ago to account for delay in changes

        # Compare the two scores and return the difference
        # If an item has regressed report it
        # If there is a new item report it

        # If there is a known item that can be fixed automatically run the fix and report it.
        # If this has affected the total score report it.
    }
}

function Get-MailSecurityReport {
    begin { Local:Enter-Scope -Invocation $MyInvocation; }
    end { Local:Exit-Scope -Invocation $MyInvocation; }

    process {
        # Get recommendded changes for normal mail security

        # Report any changes that are suggested
        # Maybe filter known changes that are ignored
    }
}

function Get-ImpersonationReport {
    begin { Local:Enter-Scope -Invocation $MyInvocation; }
    end { Local:Exit-Scope -Invocation $MyInvocation; }

    process {
        # Get impersonations from the last 30 days for domains and users
    }
}

function Get-DeviceChangesReport {
    begin { Local:Enter-Scope -Invocation $MyInvocation; }
    end { Local:Exit-Scope -Invocation $MyInvocation; }

    process {
        # Get device changes from the last 30 days

        # Changes include new devices and removed devices
    }
}

function Get-MFAChangesReport {
    Invoke-Script "mfa_compare" @{
        ClientName = $ClientName
        SharedFolder = $SharedFolder
    }
}

function Get-InteractiveSigninReport {
    begin { Local:Enter-Scope -Invocation $MyInvocation; }
    end { Local:Exit-Scope -Invocation $MyInvocation; }

    process {
        # Get interactive signins from the last 30 days
        # Filer any signins that are from known ips such as the office, or a team members home.
        # Report any signins that are not from known ips
        # Detect if an ip was used because of mobile reception
        # Detect if an ip was used because of a vpn
        # Detect if an ip was used because of a proxy
        # Group signins by user and report the number of signins from unknown ips
        # Also report if there are a large quantity of failed sign-ins from known ips

        # If there was a failed signin followed by a sucessful signin within 5 minutes, report it.
        # Group any failed signins from failed conditional geo policies and report them as a single event.

        # End the report by exporting to an excel pivot table.
        # The rows of this table should be ordered User,Location,IP Address,Status,Failure Reason
        # The Values of this table should be Count of Required ID
    }
}

function Get-Alerts {
    # Get alerts from the last 30 days
}
