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

function Format-ScopeName([Parameter(Mandatory)][Switch]$IsExit) {
    [String]$Local:CurrentScope = (Get-StackTop).MyCommand.Name;
    # Skip the first scope as it's the current scope, then sort in descending order so we can get the correct order for printing.
    [String[]]$Local:PreviousScopes = (Get-Stack).GetEnumerator() | Select-Object -Skip 1 | ForEach-Object { $_.MyCommand.Name } | Sort-Object -Descending;

    [String]$Local:Scope = "$($Local:PreviousScopes -join ' > ')$(if ($Local:PreviousScopes.Count -gt 0) { if ($IsExit) { ' < ' } else { ' > ' } })$Local:CurrentScope";
    return $Local:Scope;
}

function Format-Parameters(
    [Parameter()]
    [String[]]$IgnoreParams = @()
) {
    [System.Collections.IDictionary]$Local:Params = (Get-StackTop).BoundParameters;
    if ($null -ne $Local:Params -and $Local:Params.Count -gt 0) {
        [String[]]$Local:ParamsFormatted = $Local:Params.GetEnumerator() | Where-Object { $_.Key -notin $IgnoreParams } | ForEach-Object { "$($_.Key) = $(Format-Variable -Value $_.Value)" };
        [String]$Local:ParamsFormatted = $Local:ParamsFormatted -join "`n";

        return "$Local:ParamsFormatted";
    }

    return $null;
}

function Format-Variable([Object]$Value) {
    function Format-SingleVariable([Parameter(Mandatory)][Object]$Value) {
        switch ($Value) {
            { $_ -is [System.Collections.HashTable] } { "`n$Script:Tab$(([HashTable]$Value).GetEnumerator().ForEach({ "$($_.Key) = $($_.Value)" }) -join "`n$Script:Tab")" }

            default { $Value }
        };
    }

    if ($null -ne $Value) {
        [String]$Local:FormattedValue = if ($Value -is [Array]) {
            "$(($Value | ForEach-Object { Format-SingleVariable $_ }) -join "`n$Script:Tab")"
        } else {
            Format-SingleVariable -Value $Value;
        }

        return $Local:FormattedValue;
    };

    return $null;
}

function Get-FormattedReturnValue(
    [Parameter()]
    [Object]$ReturnValue
) {
    function Format([Object]$Value) {
        switch ($Value) {
            { $_ -is [System.Collections.HashTable] } { "`n$Script:Tab$(([HashTable]$Value).GetEnumerator().ForEach({ "$($_.Key) = $($_.Value)" }) -join "`n$Script:Tab")" }

            default { $ReturnValue }
        };
    }

    if ($null -ne $ReturnValue) {
        [String]$Local:FormattedValue = if ($ReturnValue -is [Array]) {
            "$(($ReturnValue | ForEach-Object { Format $_ }) -join "`n$Script:Tab")"
        } else {
            Format -Value $ReturnValue;
        }

        return "Return Value: $Local:FormattedValue";
    };

    return $null;
}

function Enter-Scope(
    [Parameter()][ValidateNotNull()]
    [String[]]$IgnoreParams = @(),

    [Parameter()][ValidateNotNull()]
    [System.Management.Automation.InvocationInfo]$Invocation = (Get-PSCallStack)[0].InvocationInfo
) {
    (Get-Stack).Push($Invocation);

    [String]$Local:ScopeName = Format-ScopeName -IsExit:$False;
    [String]$Local:ParamsFormatted = Format-Parameters -IgnoreParams:$IgnoreParams;

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
    [Parameter()]
    [Object]$ReturnValue
) {
    [String]$Local:ScopeName = Format-ScopeName -IsExit:$True;
    [String]$Local:ReturnValueFormatted = Format-Variable -Value:$ReturnValue;

    @{
        PSMessage   = "$Local:ScopeName$(if ($Local:ReturnValueFormatted) { "`n$Script:Tab$Local:ReturnValueFormatted" })";
        PSColour    = 'Blue';
        PSPrefix    = '❮❮';
        ShouldWrite = $Global:Logging.Verbose;
    } | Invoke-Write;

    (Get-Stack).Pop() | Out-Null;
}

Export-ModuleMember -Function Get-StackTop, Format-Parameters, Format-Variable, Format-ScopeName, Enter-Scope, Exit-Scope;
