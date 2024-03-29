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
    [String]$Local:CurrentScope = (Get-StackTop).Invocation.MyCommand.Name;
    # Skip the first scope as it's the current scope, then sort in descending order so we can get the correct order for printing.
    [String[]]$Local:PreviousScopes = (Get-Stack).GetEnumerator() | Select-Object -Skip 1 | ForEach-Object { $_.Invocation.MyCommand.Name } | Sort-Object -Descending;

    [String]$Local:Scope = "$($Local:PreviousScopes -join ' > ')$(if ($Local:PreviousScopes.Count -gt 0) { if ($IsExit) { ' < ' } else { ' > ' } })$Local:CurrentScope";
    return $Local:Scope;
}

function Format-Parameters(
    [Parameter()]
    [String[]]$IgnoreParams = @()
) {
    [System.Collections.IDictionary]$Local:Params = (Get-StackTop).Invocation.BoundParameters;
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
            { $_ -is [System.Collections.HashTable] } { "$(([HashTable]$Value).GetEnumerator().ForEach({ "$($_.Key) = $($_.Value)" }) -join "`n")" }
            default { $Value }
        };
    }

    if ($null -ne $Value) {
        [String]$Local:FormattedValue = if ($Value -is [Array]) {
            "$(($Value | ForEach-Object { Format-SingleVariable $_ }) -join "`n")"
        } else {
            Format-SingleVariable -Value $Value;
        }

        return $Local:FormattedValue;
    };

    return $null;
}

function Enter-Scope(
    [Parameter()][ValidateNotNull()]
    [String[]]$IgnoreParams = @(),

    [Parameter()]
    [ValidateNotNull()]
    [System.Management.Automation.InvocationInfo]$Invocation = (Get-PSCallStack)[0].InvocationInfo # Get's the callers invocation info.
) {
    if (-not $Global:Logging.Verbose) { return; } # If we aren't logging don't bother with the rest of the function.

    (Get-Stack).Push(@{ Invocation = $Invocation; StopWatch = [System.Diagnostics.Stopwatch]::StartNew(); });

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
    if (-not $Global:Logging.Verbose) { return; } # If we aren't logging don't bother with the rest of the function.

    [System.Diagnostics.Stopwatch]$Local:StopWatch = (Get-StackTop).StopWatch;
    $Local:StopWatch.Stop();
    [String]$Local:ExecutionTime = "Execution Time: $($Local:StopWatch.ElapsedMilliseconds)ms";

    [String]$Local:ScopeName = Format-ScopeName -IsExit:$True;
    [String]$Local:ReturnValueFormatted = Format-Variable -Value:$ReturnValue;

    [String]$Local:Message = $Local:ScopeName;
    if ($Local:ExecutionTime) {
        $Local:Message += "`n$Local:ExecutionTime";
    }
    if ($Local:ReturnValueFormatted) {
        $Local:Message += "`n$Local:ReturnValueFormatted";
    }

    @{
        PSMessage   = $Local:Message;
        PSColour    = 'Blue';
        PSPrefix    = '❮❮';
        ShouldWrite = $Global:Logging.Verbose;
    } | Invoke-Write;

    (Get-Stack).Pop() | Out-Null;
}

Export-ModuleMember -Function Get-StackTop, Format-Parameters, Format-Variable, Format-ScopeName, Enter-Scope, Exit-Scope;
