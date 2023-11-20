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

#endregion - Scope Functions

#region - Login and Password

[String]$Local:Bitwarden_CollectionID = "ce550182-2264-4b7c-8d75-af95017d451c" # Shared-All-Company/AMT

function Local:Get-AllItems {
    begin { Enter-Scope -Invocation $MyInvocation }
    end { Exit-Scope -Invocation $MyInvocation $Local:AllItems }

    process {
        $Local:AllItems = bw list items --collectionid $Local:Bitwarden_CollectionID | ConvertFrom-Json

        # Assert stuff

        return $Local:AllItems
    }
}

function Get-Login_O365Admin_All {
    begin { Enter-Scope -Invocation $MyInvocation }
    end { Exit-Scope -Invocation $MyInvocation $Local:Items }

    process {
        return Get-AllItems -CollectionID $Local:Bitwarden_CollectionID | Where-Object { $_.name -contains "O365 Admin - " }
    }
}

function Get-Login_O365Admin([Parameter(Mandatory)][String]$Company) {
    begin { Enter-Scope -Invocation $MyInvocation }
    end { Exit-Scope -Invocation $MyInvocation $Local:Items }

    process {
        $Company | Local:Assert-NotNull "Company was null";

        [PSCustomObject]$Local:Item = Get-AllItems -CollectionID $Local:Bitwarden_CollectionID | Where-Object {
            [String[]]$Local:Split = $_.name | Split-String -Separator " - ";
            $Local:Split[0] -eq "O365 Admin" -and $Local:Split[1] -like $Company
        }

        return Get-AllItems -CollectionID $Local:Bitwarden_CollectionID | Where-Object { $_.name -eq "O365 Admin" -and $_.notes -eq $Company }
    }
}

#endregion - Login and Password

#region - Multi-factor Authentication



#endregion - Multi-factor Authentication
