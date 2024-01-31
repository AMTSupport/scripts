#Requires -Version 5.1

[System.Collections.Stack]$Script:InvocationStack = [System.Collections.Stack]::new();
[String]$Script:Tab = "  ";

# Used so we can mock in tests.
function Get-Stack {
    Get-Variable -Name 'InvocationStack' -ValueOnly;
}

function Get-StackTop {;
    return (Get-Stack).Peek()
}

function Get-ScopeNameFormatted([Parameter(Mandatory)][Switch]$IsExit) {
    [String]$Local:CurrentScope = (Get-StackTop).MyCommand.Name;
    [String[]]$Local:PreviousScopes = (Get-Stack).GetEnumerator() | ForEach-Object { $_.MyCommand } | Sort-Object -Descending -Property Name | Select-Object -SkipLast 1;

    [String]$Local:Scope = "$($Local:PreviousScopes -join ' > ')$(if ($Local:PreviousScopes.Count -gt 0) { if ($IsExit) { ' < ' } else { ' > ' } })$Local:CurrentScope";
    return $Local:Scope;
}

function Get-FormattedParameters {
    [System.Collections.IDictionary]$Local:Params = (Get-StackTop).BoundParameters;
    if ($null -ne $Local:Params -and $Local:Params.Count -gt 0) {
        [String[]]$Local:ParamsFormatted = $Local:Params.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)" };
        [String]$Local:ParamsFormatted = $Local:ParamsFormatted -join "`n";

        return "$Local:ParamsFormatted";
    }

    return $null;
}

function Get-FormattedReturnValue(
    [Parameter()]
    [Object]$ReturnValue
) {
    if ($null -ne $ReturnValue) {
        [String]$Local:FormattedValue = switch ($ReturnValue) {
            { $_ -is [System.Collections.Hashtable] } { "`n$Script:Tab$(([HashTable]$ReturnValue).GetEnumerator().ForEach({ "$($_.Key) = $($_.Value)" }) -join "`n$Script:Tab")" }
            { $_ -is [Object[]] } { "`n$Script:Tab$($ReturnValue -join "`n$Script:Tab")" }

            default { $ReturnValue }
        };

        return "Return Value: $Local:FormattedValue";
    };

    return $null;
}

function Enter-Scope(
    [Parameter()][ValidateNotNull()]
    [System.Management.Automation.InvocationInfo]$Invocation = (Get-PSCallStack)[0].InvocationInfo
) {
    (Get-Stack).Push($Invocation);

    [String]$Local:ScopeName = Get-ScopeNameFormatted -IsExit:$False;
    [String]$Local:ParamsFormatted = Get-FormattedParameters;

    @{
        PSMessage   = "$Local:ScopeName$(if ($Local:ParamsFormatted) { "`n$Local:ParamsFormatted" })";
        PSColour    = 'Blue';
        PSPrefix    = '❯❯';
        ShouldWrite = $Global:Logging.Verbose;
    } | Invoke-Write;
}

function Exit-Scope(
    [Parameter()][ValidateNotNull()]
    [System.Management.Automation.InvocationInfo]$Invocation = (Get-PSCallStack)[0].InvocationInfo,
    [Parameter()][ValidateNotNull()]
    [Object]$ReturnValue
) {
    [String]$Local:ScopeName = Get-ScopeNameFormatted -IsExit:$True;
    [String]$Local:ReturnValueFormatted = Get-FormattedReturnValue -ReturnValue $ReturnValue;

    @{
        PSMessage   = "$Local:ScopeName$(if ($Local:ReturnValueFormatted) { "`n$Script:Tab$Local:ReturnValueFormatted" })";
        PSColour    = 'Blue';
        PSPrefix    = '❮❮';
        ShouldWrite = $Global:Logging.Verbose;
    } | Invoke-Write;

    (Get-Stack).Pop() | Out-Null;
}

Export-ModuleMember -Function Get-StackTop, Get-FormattedParameters, Get-FormattedReturnValue, Get-ScopeNameFormatted, Enter-Scope,Exit-Scope;
