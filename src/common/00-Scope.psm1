#Requires -Version 5.1

function Local:Get-ScopeNameFormatted(
    [Parameter(Mandatory)][ValidateNotNull()]
    [System.Management.Automation.InvocationInfo]$Invocation
) {
    [String]$ScopeName = $Invocation.MyCommand.Name;
    [String]$ScopeName = if ($null -ne $ScopeName) { "Scope: $ScopeName" } else { 'Scope: Unknown' };

    return $ScopeName;
}

function Enter-Scope(
    [Parameter(Mandatory)][ValidateNotNull()]
    [System.Management.Automation.InvocationInfo]$Invocation
) {
    [String]$Local:ScopeName = Get-ScopeNameFormatted -Invocation $Invocation;
    [System.Collections.IDictionary]$Local:Params = $Invocation.BoundParameters;

    [String]$Local:ParamsFormatted = if ($null -ne $Params -and $Params.Count -gt 0) {
        [String[]]$ParamsFormatted = $Params.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)" };
        [String]$Local:ParamsFormatted = $Local:ParamsFormatted -join "`n`t";

        "Parameters: $Local:ParamsFormatted";
    } else { 'Parameters: None'; }

    Invoke-Verbose "Entered Scope`n`t$ScopeName`n`t$ParamsFormatted";
}

function Exit-Scope(
    [Parameter(Mandatory)][ValidateNotNull()]
    [System.Management.Automation.InvocationInfo]$Invocation,

    [Object]$ReturnValue
) {
    [String]$Local:ScopeName = Get-ScopeNameFormatted -Invocation $Invocation;
    if ($null -ne $ReturnValue) {
        [String]$Local:FormattedValue = switch ($ReturnValue) {
            { $_ -is [System.Collections.Hashtable] } { "`n`t$(([HashTable]$ReturnValue).GetEnumerator().ForEach({ "$($_.Key) = $($_.Value)" }) -join "`n`t")" }
            default { $ReturnValue }
        };

        [String]$Local:ReturnValueFormatted = "Return Value: $Local:FormattedValue";
    } else { [String]$Local:ReturnValueFormatted = 'Return Value: None'; };

    Invoke-Verbose "Exited Scope`n`t$ScopeName`n`t$ReturnValueFormatted";
}

Export-ModuleMember -Function Enter-Scope,Exit-Scope;
