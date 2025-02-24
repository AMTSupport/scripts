Using module .\PSStyle.psm1
Using module @{
    ModuleName      = 'PSReadLine';
    ModuleVersion = '2.3.2';
}

function Test-IsNableRunner {
    $WindowName = $Host.UI.RawUI.WindowTitle;
    if (-not $WindowName) { return $False; };
    return ($WindowName | Split-Path -Leaf) -eq 'fmplugin.exe';
}

<#
.SYNOPSIS
    Gets whether the current terminal supports Unicode characters.
.NOTES
    FIXME: Still displays Unicode characters in the powershell console.
#>
function Test-SupportsUnicode {
    $null -ne $env:WT_SESSION -and -not (Test-IsNableRunner);
}

function Test-SupportsColour {
    -not (Test-IsNableRunner);
}

function Invoke-Write {
    [CmdletBinding(PositionalBinding, DefaultParameterSetName = 'Splat')]
    param (
        [Parameter(ParameterSetName = 'InputObject', Position = 0, ValueFromPipeline)]
        [HashTable]$InputObject,

        [Parameter(ParameterSetName = 'Splat', Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String]$PSMessage,

        [Parameter(ParameterSetName = 'Splat', ValueFromPipelineByPropertyName, HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
        [String]$PSPrefix,

        [Parameter(ParameterSetName = 'Splat', Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String]$PSColour,

        [Parameter(ParameterSetName = 'Splat', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Boolean]$ShouldWrite,

        [Parameter(ParameterSetName = 'Splat', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Switch]$PassThru
    )

    process {
        if ($InputObject) {
            Invoke-Write @InputObject;
            return;
        }

        # If PassThru is set, we should always return the message.
        if (-not $ShouldWrite -and -not $PassThru) {
            return;
        }

        [String]$Local:NewLineTab = if ($PSPrefix -and (Test-SupportsUnicode)) {
            "$(' ' * $($PSPrefix.Length))";
        } else { ''; }

        [String]$Local:FormattedMessage = if ($PSMessage.Contains("`n")) {
            $PSMessage -replace "`n", "`n$Local:NewLineTab+ ";
        } else { $PSMessage; }

        if (Test-SupportsColour) {
            $Local:FormattedMessage = "$(Get-ConsoleColour $PSColour)$Local:FormattedMessage$($PSStyle.Reset)";
        }

        [String]$Local:FormattedMessage = if ($PSPrefix -and (Test-SupportsUnicode)) {
            "$PSPrefix $Local:FormattedMessage";
        } else { $Local:FormattedMessage; }

        if ($PassThru) {
            return $Local:FormattedMessage;
        } else {
            $InformationPreference = 'Continue';
            Write-Information $Local:FormattedMessage;
        }
    }
}

function Format-Error(
    [Parameter(Mandatory, HelpMessage = 'The error records invocation info.')]
    [ValidateNotNullOrEmpty()]
    [System.Management.Automation.InvocationInfo]$InvocationInfo,

    [Parameter(HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
    [ValidateNotNullOrEmpty()]
    [String]$Message,

    [Parameter(HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
    [ValidateNotNullOrEmpty()]
    [Alias('Prefix')]
    [String]$UnicodePrefix,

    [Parameter(HelpMessage = 'Return the formatted message instead of writing it to the console.')]
    [Switch]$PassThru
) {
    [String]$Local:TrimmedLine = $InvocationInfo.Line.Trim();
    [String]$Local:Script = $InvocationInfo.ScriptName.Trim();

    if ($InvocationInfo.Statement) {
        [String]$Local:Statement = $InvocationInfo.Statement.Trim();

        # Find where the statement matches in the line, and underline it, indent the statement to where it matches in the line.
        [Int]$Local:StatementIndex = $Local:TrimmedLine.IndexOf($Local:Statement);

        # FIXME: This is a hack to fix the issue where the statement index is -1, this shouldn't happen!
        if ($Local:StatementIndex -lt 0) {
            [Int]$Local:StatementIndex = 0;
        }
    } else {
        [Int]$Local:StatementIndex = 0;
        [String]$Local:Statement = $TrimmedLine;
    }

    # FIXME : If the statement is larger than the width it starts cutting it off from the right side.
    # Remove 10 from the total width to allow for padding & line context.
    # Then an additional 6 to account for possible ellipsis.
    $Padding = 16;
    $Local:ConsoleWidth = $Host.UI.RawUI.BufferSize.Width - $Padding;
    if ($Local:TrimmedLine.Length -gt $Local:ConsoleWidth) {

        $Local:TrimLength = $Local:TrimmedLine.Length - $Local:ConsoleWidth;
        $Local:LeftSide = $Local:StatementIndex - 1;
        $Local:RightSide = $Local:TrimmedLine.Length - $Local:StatementIndex - $Local:Statement.Length;

        $GreaterSide;
        $LesserSide;
        if ($LeftSide -ge $RightSide) {
            $GreaterSide = $LeftSide;
            $LesserSide = $RightSide;
        } else {
            $GreaterSide = $RightSide;
            $LesserSide = $LeftSide;
        };
        $Difference = [System.Math]::Min($GreaterSide - $LesserSide, $TrimLength);

        $StartIndex = 0;
        $EndIndex = $TrimmedLine.Length - $Difference;
        if ($GreaterSide -eq $LeftSide) {
            $TrimLength -= $Difference;
            $StartIndex = $Difference;
            $Local:StatementIndex -= $Difference;

            if ($TrimLength -gt 0) {
                $FromEachSide = [System.Math]::Ceiling($TrimLength / 2);
                $EndIndex -= $TrimLength;
                $StartIndex += $FromEachSide;
                $Local:StatementIndex -= $FromEachSide;
            }
        } else {
            $TrimLength -= $Difference;

            if ($TrimLength -gt 0) {
                $FromEachSide = [System.Math]::Ceiling($TrimLength / 2);
                $EndIndex -= $TrimLength;
                $StartIndex += $FromEachSide;
                $Local:StatementIndex -= $FromEachSide;
            }
        }

        $Local:TrimmedLine = $Local:TrimmedLine.Substring($StartIndex, $EndIndex);

        # If either side is trimmed then add the ellipsis.
        if ($StartIndex -gt 0) {
            $Local:TrimmedLine = "...$Local:TrimmedLine";
            $Local:StatementIndex += 3;
        }
        if ($EndIndex -lt $Local:TrimmedLine.Length) {
            $Local:TrimmedLine = "$Local:TrimmedLine...";
        }
    }

    [String]$Local:Underline = (' ' * ($Local:StatementIndex + 10)) + ('^' * $Local:Statement.Length);

    # Position the message to the same indent as the statement.
    [String]$Local:Message = if ($null -ne $Message) {
        (' ' * $Local:StatementIndex) + $Message;
    } else { $null };

    # Fucking PS 5 doesn't allow variable overrides so i have to add the colour to all of them. :<(
    [HashTable]$Private:BaseArgs = @{
        PSPrefix    = if ($UnicodePrefix) { $UnicodePrefix } else { $null };
        ShouldWrite = $True;
        PassThru    = $PassThru;
    };

    Invoke-Write @Private:BaseArgs -PSMessage "File    | $($PSStyle.Foreground.Red)$Local:Script" -PSColour Cyan;
    Invoke-Write @Private:BaseArgs -PSMessage "Line    | $($PSStyle.Foreground.Red)$($InvocationInfo.ScriptLineNumber)" -PSColour Cyan;
    Invoke-Write @Private:BaseArgs -PSMessage "Preview | $($PSStyle.Foreground.Red)$Local:TrimmedLine" -PSColour Cyan;
    Invoke-Write @Private:BaseArgs -PSMessage "$Local:Underline" -PSColour 'Red';

    if ($Local:Message) {
        # TODO - If the message is too long and would be a multiline, add extra rows and indent properly.
        Invoke-Write @Private:BaseArgs -PSMessage "Message | $($PSStyle.Foreground.Red)$Local:Message" -PSColour Cyan;
    }
}

function Invoke-Verbose {
    [CmdletBinding(PositionalBinding, DefaultParameterSetName = 'Splat')]
    param(
        [Parameter(ParameterSetName = 'InputObject', Position = 0, ValueFromPipeline)]
        [HashTable]$InputObject,

        [Parameter(ParameterSetName = 'Splat', Position = 0, ValueFromPipelineByPropertyName, Mandatory, HelpMessage = 'The message to write to the console.')]
        [ValidateNotNullOrEmpty()]
        [String]$Message,

        [Parameter(ParameterSetName = 'Splat', Position = 1, ValueFromPipelineByPropertyName, HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
        [ValidateNotNullOrEmpty()]
        [Alias('Prefix')]
        [String]$UnicodePrefix,

        [Parameter(ValueFromPipelineByPropertyName, HelpMessage = 'Return the formatted message instead of writing it to the console.')]
        [Switch]$PassThru
    )

    process {
        if ($InputObject) {
            Invoke-Verbose @InputObject;
            return;
        }

        $Local:Params = @{
            PSPrefix    = if ($UnicodePrefix) { $UnicodePrefix } else { '🔍' };
            PSMessage   = $Message;
            PSColour    = 'Yellow';
            ShouldWrite = $PSCmdlet.GetVariableValue('VerbosePreference') -notmatch 'SilentlyContinue|Ignore';
            PassThru    = $PassThru;
        };

        Invoke-Write @Local:Params;
    }
}

function Invoke-Debug {
    [CmdletBinding(PositionalBinding, DefaultParameterSetName = 'Splat')]
    param(
        [Parameter(ParameterSetName = 'InputObject', Position = 0, ValueFromPipeline)]
        [HashTable]$InputObject,

        [Parameter(ParameterSetName = 'Splat', Position = 0, ValueFromPipelineByPropertyName, Mandatory, HelpMessage = 'The message to write to the console.')]
        [ValidateNotNullOrEmpty()]
        [String]$Message,

        [Parameter(ParameterSetName = 'Splat', Position = 1, ValueFromPipelineByPropertyName, HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
        [ValidateNotNullOrEmpty()]
        [Alias('Prefix')]
        [String]$UnicodePrefix,

        [Parameter(HelpMessage = 'Return the formatted message instead of writing it to the console.')]
        [Switch]$PassThru
    )

    process {
        if ($InputObject) {
            Invoke-Debug @InputObject;
            return;
        }

        $Local:Params = @{
            PSPrefix    = if ($UnicodePrefix) { $UnicodePrefix } else { '🐛' };
            PSMessage   = $Message;
            PSColour    = 'Magenta';
            ShouldWrite = $PSCmdlet.GetVariableValue('DebugPreference') -notmatch 'SilentlyContinue|Ignore';
            PassThru    = $PassThru;
        };

        Invoke-Write @Local:Params;
    }
}

function Invoke-Info {
    [CmdletBinding(PositionalBinding, DefaultParameterSetName = 'Splat')]
    param(
        [Parameter(ParameterSetName = 'InputObject', Position = 0, ValueFromPipeline)]
        [HashTable]$InputObject,

        [Parameter(ParameterSetName = 'Splat', Position = 0, ValueFromPipelineByPropertyName, Mandatory, HelpMessage = 'The message to write to the console.')]
        [ValidateNotNullOrEmpty()]
        [String]$Message,

        [Parameter(ParameterSetName = 'Splat', Position = 1, ValueFromPipelineByPropertyName, HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
        [ValidateNotNullOrEmpty()]
        [Alias('Prefix')]
        [String]$UnicodePrefix,

        [Parameter(HelpMessage = 'Return the formatted message instead of writing it to the console.')]
        [Switch]$PassThru
    )

    process {
        if ($InputObject) {
            Invoke-Info @InputObject;
            return;
        }

        $Local:Params = @{
            PSPrefix    = if ($UnicodePrefix) { $UnicodePrefix } else { 'ℹ️' };
            PSMessage   = $Message;
            PSColour    = 'Cyan';
            ShouldWrite = $PSCmdlet.GetVariableValue('InformationPreference') -ne 'Ignore'
            PassThru    = $PassThru;
        };

        Invoke-Write @Local:Params;
    }
}

function Invoke-Warn {
    [CmdletBinding(PositionalBinding, DefaultParameterSetName = 'Splat')]
    param(
        [Parameter(ParameterSetName = 'InputObject', Position = 0, ValueFromPipeline)]
        [HashTable]$InputObject,

        [Parameter(ParameterSetName = 'Splat', Position = 0, ValueFromPipelineByPropertyName, Mandatory, HelpMessage = 'The message to write to the console.')]
        [ValidateNotNullOrEmpty()]
        [String]$Message,

        [Parameter(ParameterSetName = 'Splat', Position = 1, ValueFromPipelineByPropertyName, HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
        [ValidateNotNullOrEmpty()]
        [Alias('Prefix')]
        [String]$UnicodePrefix,

        [Parameter(HelpMessage = 'Return the formatted message instead of writing it to the console.')]
        [Switch]$PassThru
    )

    process {
        if ($InputObject) {
            Invoke-Warn @InputObject;
            return;
        }

        $Local:Params = @{
            PSPrefix    = if ($UnicodePrefix) { $UnicodePrefix } else { '⚠️' };
            PSMessage   = $Message;
            PSColour    = 'Yellow';
            ShouldWrite = $PSCmdlet.GetVariableValue('WarningPreference') -notmatch 'SilentlyContinue|Ignore';
            PassThru    = $PassThru;
        };

        Invoke-Write @Local:Params;
    }
}

function Invoke-Error {
    [CmdletBinding(PositionalBinding, DefaultParameterSetName = 'Splat')]
    param(
        [Parameter(ParameterSetName = 'InputObject', Position = 0, ValueFromPipeline)]
        [HashTable]$InputObject,

        [Parameter(ParameterSetName = 'Splat', Position = 0, ValueFromPipelineByPropertyName, Mandatory, HelpMessage = 'The message to write to the console.')]
        [ValidateNotNullOrEmpty()]
        [String]$Message,

        [Parameter(ParameterSetName = 'Splat', Position = 1, ValueFromPipelineByPropertyName, HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
        [ValidateNotNullOrEmpty()]
        [Alias('Prefix')]
        [String]$UnicodePrefix,

        [Parameter(HelpMessage = 'Return the formatted message instead of writing it to the console.')]
        [Switch]$PassThru
    )

    process {
        if ($InputObject) {
            Invoke-Error @InputObject;
            return;
        }

        $Local:Params = @{
            PSPrefix    = if ($UnicodePrefix) { $UnicodePrefix } else { '❌' };
            PSMessage   = $Message;
            PSColour    = 'Red';
            ShouldWrite = $ErrorActionPreference -ne 'SilentlyContinue';
            PassThru    = $PassThru;
        };

        Invoke-Write @Local:Params;
    }
}

function Invoke-Timeout {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, HelpMessage = 'The timeout in milliseconds.')]
        [ValidateNotNullOrEmpty()]
        [Int]$Timeout,

        [Parameter(Mandatory, HelpMessage = 'The message to write to the console.')]
        [ValidateNotNullOrEmpty()]
        [String]$Activity,
        [Parameter(Mandatory, HelpMessage = 'The format string to use when writing the status message, must contain a single placeholder for the time left in seconds.')]
        [ValidateNotNullOrEmpty()]
        [String]$StatusMessage,

        [Parameter(HelpMessage = 'The ScriptBlock to invoke when the timeout is reached and wasn''t cancelled.')]
        [ScriptBlock]$TimeoutScript,

        [Parameter(ParameterSetName = 'Cancellable', HelpMessage = 'The ScriptBlock to invoke if the timeout was cancelled.')]
        [ScriptBlock]$CancelScript,
        [Parameter(ParameterSetName = 'Cancellable', HelpMessage = 'If the timeout is cancellable.')]
        [Switch]$AllowCancel
    )

    process {
        # Ensure that the input buffer is flushed, otherwise the user can press escape before the loop starts and it would cancel it.
        $Host.UI.RawUI.FlushInputBuffer();

        [String]$Local:Prefix = if ($AllowCancel) { '⏳' } else { '⏲️' };

        if ($AllowCancel) {
            Invoke-Info -Message "$Activity is cancellable, press any key to cancel." -UnicodePrefix $Local:Prefix;
        }

        [TimeSpan]$Local:TimeInterval = [TimeSpan]::FromMilliseconds(50);
        [TimeSpan]$Local:TimeLeft = [TimeSpan]::FromSeconds($Timeout);
        do {
            [DateTime]$Local:StartAt = Get-Date;

            if ($AllowCancel -and [Console]::KeyAvailable) {
                Invoke-Debug -Message 'Timeout cancelled by user.';
                break;
            }

            Write-Progress `
                -Activity $Activity `
                -Status ($StatusMessage -f ([Math]::Floor($Local:TimeLeft.TotalSeconds))) `
                -PercentComplete ($Local:TimeLeft.TotalMilliseconds / ($Timeout * 10)) `
                -Completed:($Local:TimeLeft.TotalMilliseconds -eq 0)

            [TimeSpan]$Local:ElaspedTime = (Get-Date) - $Local:StartAt;
            [TimeSpan]$Local:IntervalMinusElasped = ($Local:TimeInterval - $Local:ElaspedTime);

            if ($Local:IntervalMinusElasped.TotalMilliseconds -gt 0) {
                $Local:TimeLeft -= $Local:IntervalMinusElasped;

                # Can't use -duration because it isn't available in PS 5.1
                Start-Sleep -Milliseconds $Local:IntervalMinusElasped.TotalMilliseconds;
            } else {
                $Local:TimeLeft -= $Local:ElaspedTime;
            }
        } while ($Local:TimeLeft.TotalMilliseconds -gt 0)

        Invoke-Debug "Finished waiting for $Activity, time left: $Local:TimeLeft.";

        if ($Local:TimeLeft -le 0) {
            Invoke-Verbose -Message 'Timeout reached, invoking timeout script if one is present.' -UnicodePrefix $Local:Prefix;
            if ($TimeoutScript) {
                & $TimeoutScript;
            }
        } elseif ($AllowCancel) {
            Invoke-Verbose -Message 'Timeout cancelled, invoking cancel script if one is present.' -UnicodePrefix $Local:Prefix;
            if ($CancelScript) {
                & $CancelScript;
            }
        }

        Write-Progress -Activity $Activity -Completed;
    }
}

function Invoke-Progress {
    Param(
        [Parameter(HelpMessage = 'The ID of the progress bar, used to display multiple progress bars at once.')]
        [Int]$Id = 0,

        [Parameter(HelpMessage = 'The activity to display in the progress bar.')]
        [String]$Activity,

        [Parameter(HelpMessage = '
            The status message to display in the progress bar.
            This is formatted with three placeholders:
                The current completion percentage.
                The index of the item being processed.
                The total number of items being processed.
        ')]
        [String]$Status,

        [Parameter(Mandatory, HelpMessage = 'The ScriptBlock which returns the items to process.')]
        [ValidateNotNull()]
        [ScriptBlock]$Get,

        [Parameter(Mandatory, HelpMessage = 'The ScriptBlock to process each item.')]
        [ValidateNotNull()]
        [ScriptBlock]$Process,

        [Parameter(HelpMessage = 'The ScriptBlock that formats the items name for the progress bar.')]
        [ValidateNotNull()]
        [ScriptBlock]$Format,

        [Parameter(HelpMessage = 'The ScriptBlock to invoke when an item fails to process.')]
        [ScriptBlock]$FailedProcessItem
    )

    process {
        if (-not $Activity) {
            $Local:FuncName = (Get-PSCallStack)[1].InvocationInfo.MyCommand.Name;
            $Activity = if (-not $Local:FuncName) {
                'Main';
            } else { $Local:FuncName; }
        }

        Write-Progress -Id:$Id -Activity:$Activity -CurrentOperation 'Getting items...' -PercentComplete 0;
        [Object[]]$Local:InputItems = $Get.InvokeReturnAsIs();
        Write-Progress -Id:$Id -Activity:$Activity -PercentComplete 1;

        if ($null -eq $Local:InputItems -or $Local:InputItems.Count -eq 0) {
            Write-Progress -Id:$Id -Activity:$Activity -Status 'No items found.' -PercentComplete 100 -Completed;
            return;
        } else {
            Write-Progress -Id:$Id -Activity:$Activity -Status "Processing $($Local:InputItems.Count) items...";
        }

        [System.Collections.IList]$Local:FailedItems = New-Object System.Collections.Generic.List[System.Object];

        [Double]$Local:PercentPerItem = 99 / $Local:InputItems.Count;
        [Double]$Local:PercentComplete = 0;

        [TimeSpan]$Local:TotalTime = [TimeSpan]::FromSeconds(0);
        [Int]$Local:ItemsProcessed = 0;

        foreach ($Item in $Local:InputItems) {
            [String]$ItemName;
            [TimeSpan]$Local:TimeTaken = (Measure-Command {
                    $ItemName = if ($Format) { $Format.InvokeReturnAsIs($Item) } else { $Item; };
                });
            $Local:TotalTime += $Local:TimeTaken;
            $Local:ItemsProcessed++;

            # Calculate the estimated time remaining
            $Local:AverageTimePerItem = $Local:TotalTime / $Local:ItemsProcessed;
            $Local:ItemsRemaining = $Local:InputItems.Count - $Local:ItemsProcessed;
            $Local:EstimatedTimeRemaining = $Local:AverageTimePerItem * $Local:ItemsRemaining

            Invoke-Debug "Items remaining: $Local:ItemsRemaining";
            Invoke-Debug "Average time per item: $Local:AverageTimePerItem";
            Invoke-Debug "Estimated time remaining: $Local:EstimatedTimeRemaining";

            $Local:Params = @{
                Id               = $Id;
                Activity         = $Activity;
                CurrentOperation = "Processing [$ItemName]...";
                SecondsRemaining = $Local:EstimatedTimeRemaining.TotalSeconds;
                PercentComplete  = [Math]::Ceiling($Local:PercentComplete);
            };

            if ($Status) {
                $Local:Params.Status = ($Status -f @($Local:PercentComplete, ($Local:InputItems.IndexOf($Item) + 1), $Local:InputItems.Count));
            }

            Write-Progress @Local:Params;

            try {
                $ErrorActionPreference = 'Stop';
                $Process.InvokeReturnAsIs($Item);
            } catch {
                Invoke-Warn "Failed to process item [$ItemName]";
                Invoke-Debug -Message "Due to reason - $($_.Exception.Message)";
                try {
                    $ErrorActionPreference = 'Stop';

                    if ($null -eq $FailedProcessItem) {
                        $Local:FailedItems.Add($Item);
                    } else { $FailedProcessItem.InvokeReturnAsIs($Item); }
                } catch {
                    Invoke-Warn "Failed to process item [$ItemName] in failed process item block";
                }
            }

            $Local:PercentComplete += $Local:PercentPerItem;
        }
        Write-Progress -Id:$Id -Activity:$Activity -PercentComplete 100 -Completed;

        if ($Local:FailedItems.Count -gt 0) {
            Invoke-Warn "Failed to process $($Local:FailedItems.Count) items";
            Invoke-Warn "Failed items: `n`t$($Local:FailedItems -join "`n`t")";
        }
    }
}

Export-ModuleMember -Function Test-SupportsUnicode, Test-SupportsColour, Invoke-Write, Invoke-Verbose, Invoke-Debug, Invoke-Info, Invoke-Warn, Invoke-Error, Format-Error, Invoke-Timeout, Invoke-Progress -Variable Logging;
