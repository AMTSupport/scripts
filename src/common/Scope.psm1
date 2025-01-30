#Requires -Version 5.1

Using module .\Logging.psm1

[System.Collections.Stack]$Script:InvocationStack = [System.Collections.Stack]::new();
[String]$Script:Tab = '  ';

# Used so we can mock in tests.
function Get-Stack {
    Get-Variable -Name 'InvocationStack' -ValueOnly;
}

function Get-StackTop {
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
    [String[]]$IgnoreParams = @(),

    [Parameter()]
    [HashTable]$ArgumentFormatter
) {
    [System.Collections.IDictionary]$Local:Params = (Get-StackTop).Invocation.BoundParameters;
    if ($null -ne $Local:Params -and $Local:Params.Count -gt 0) {
        [String]$Local:ParamsFormatted = ($Local:Params.GetEnumerator() `
            | Where-Object { $_.Key -notin $IgnoreParams } `
            | ForEach-Object {
                $Local:Formatter = $ArgumentFormatter[$_.Key];
                $Local:FormattedValue = Format-Variable -Value:$_.Value -Formatter:$Local:Formatter;
                "$($_.Key) = $Local:FormattedValue";
            }) `
            -join "`n";

        return "$Local:ParamsFormatted";
    }

    return $null;
}

function Format-Variable(
    [Parameter()]
    [Object]$Value,
    [Parameter()]
    [ScriptBlock]$Formatter,

    [Parameter(DontShow)]
    [Int]$CallDepth = 0,

    [Parameter(DontShow)]
    [Switch]$Appending
) {
    [String]$Local:FullIndent = $Script:Tab * ($CallDepth + 1);
    [String]$Local:AppendingIndent = if (-not $Appending -and $CallDepth -gt 0) { $Local:FullIndent } else { '' };
    [String]$Local:EndingIndent = $Script:Tab * $CallDepth;

    if ($null -ne $Value) {
        [String]$Local:FormattedValue = switch ($Value) {
            { $Value -is [Array] } {
                [String[]]$Private:Values = $Value | ForEach-Object { Format-Variable -Value:$_ -Formatter:$Formatter -CallDepth:($CallDepth + 1) -Appending; };

                if ($Private:Values.Count -eq 0) {
                    return "$Local:AppendingIndent[]";
                }

                @"
$Local:AppendingIndent[
$Local:FullIndent$($Private:Values -join ",`n$Local:FullIndent")
$Local:EndingIndent]
"@;
                break;
            }
            { $Value -is [HashTable] } {
                [String[]]$Private:Pairs = $Value.GetEnumerator() | ForEach-Object {
                    $Private:Key = $_.Key;
                    $Private:Value = $_.Value;

                    "$Private:Key = $(Format-Variable -Value:$Private:Value -Formatter:$Formatter -CallDepth:($CallDepth + 1) -Appending)"
                };

                if ($Private:Pairs.Count -eq 0) {
                    return "$Local:AppendingIndent{}";
                }

                @"
$Local:AppendingIndent{
$Local:FullIndent$($Private:Pairs -join "`n$Local:FullIndent")
$Local:EndingIndent}
"@;
                break;
            }
            default {
                if ($null -ne $Formatter) {
                    $Formatter.InvokeWithContext($null, [PSVariable]::new('_', $Value));
                } else {
                    $Value;
                }

                break;
            }
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
    [System.Management.Automation.InvocationInfo]$Invocation = (Get-PSCallStack)[0].InvocationInfo, # Get's the callers invocation info.

    [Parameter()]
    [HashTable]$ArgumentFormatter,

    [Parameter()]
    [Switch]$PassThru
) {
    (Get-Stack).Push(@{ Invocation = $Invocation; StopWatch = [System.Diagnostics.Stopwatch]::StartNew(); });

    if (-not $Global:Logging.Verbose) { return; } # If we aren't logging don't bother with the rest of the function.
    if ($null -eq $ArgumentFormatter) {
        $ArgumentFormatter = @{};
    }

    [String]$Local:ScopeName = Format-ScopeName -IsExit:$False;
    [String]$Local:ParamsFormatted = Format-Parameters -IgnoreParams:$IgnoreParams -ArgumentFormatter:$ArgumentFormatter;

    @{
        PSMessage   = "$Local:ScopeName$(if ($Local:ParamsFormatted) { "`n$Local:ParamsFormatted" })";
        PSColour    = 'Blue';
        PSPrefix    = '❯❯';
        ShouldWrite = $Global:Logging.Verbose;
        PassThru    = $PassThru;
    } | Invoke-Write;
}

function Exit-Scope(
    [Parameter()]
    [Object]$ReturnValue
) {
    [System.Diagnostics.Stopwatch]$Local:StopWatch = (Get-StackTop).StopWatch;
    $Local:StopWatch.Stop();

    if ($Global:Logging.Verbose) {
        if ($null -eq $ArgumentFormatter) {
            $ArgumentFormatter = @{};
        }

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
    }

    (Get-Stack).Pop() | Out-Null;
}

Export-ModuleMember -Function Get-StackTop, Format-Parameters, Format-Variable, Format-ScopeName, Enter-Scope, Exit-Scope;
