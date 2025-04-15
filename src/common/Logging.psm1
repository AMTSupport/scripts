Using module .\PSStyle.psm1;

Using module @{
    ModuleName    = 'PSReadLine';
    ModuleVersion = '2.3.2';
}

<#
.SYNOPSIS
    Writes a message to the console or returns it, based on provided parameters.

.DESCRIPTION
    This function processes a message with optional colour, prefix, and pass-through behavior.
    If PassThru is specified, the function returns the message instead of writing it to the console.

.PARAMETER InputObject
    A hashtable of parameters to be splatted into Invoke-Write. When passed, all other parameters are ignored.

.PARAMETER PSMessage
    Specifies the message to be logged.

.PARAMETER PSPrefix
    An optional Unicode prefix (e.g., emoji) to prepend to the output if Unicode is supported.

.PARAMETER PSColour
    Specifies the color of the message text if colour output is supported.

.PARAMETER MultiLineIndent
    Sets the number of characters to indent multiline message lines.

.PARAMETER ShouldWrite
    Indicates whether the function should write the message to the console.

.PARAMETER PassThru
    When set, returns the formatted message instead of writing it to the console.

.EXAMPLE
    ```powershell
    Invoke-Write -PSMessage "Hello World" -PSColour "Cyan" -ShouldWrite $True
    ```

.EXAMPLE
    ```powershell
    Invoke-Write @{ PSMessage = "Hello World"; PSColour = "Green"; PassThru = $true; ShouldWrite = $True }
    ```

#>
function Invoke-Write {
    [CmdletBinding(PositionalBinding, DefaultParameterSetName = 'Splat')]
    param (
        [Parameter(ParameterSetName = 'InputObject', Position = 0, ValueFromPipeline)]
        [HashTable]$InputObject,

        [Parameter(ParameterSetName = 'Splat', Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String]$PSMessage,

        [Parameter(ParameterSetName = 'Splat', ValueFromPipelineByPropertyName)]
        [String]$PSPrefix,

        [Parameter(ParameterSetName = 'Splat', Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String]$PSColour,

        [Parameter(ParameterSetName = 'Splat', ValueFromPipelineByPropertyName)]
        [Int]$MultiLineIndent = 0,

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

        if (-not $ShouldWrite) {
            return;
        }

        [String]$Local:NewLineTab = if ($PSPrefix -and (Test-SupportsUnicode)) {
            "$(' ' * $(($PSPrefix.Length + $MultiLineIndent)))";
        } else { (' ' * $MultiLineIndent); }

        [String]$Local:FormattedMessage = if ($PSMessage.Contains("`n")) {
            $PSMessage -replace "`n", "`n$Local:NewLineTab+ ";
        } else { $PSMessage; }

        if (Test-SupportsColour) {
            $ColourSeq = [PSStyle]::MapForegroundColorToEscapeSequence($PSColour);
            # If the string contains any instances of PSStyle.Reset we need to add the colour sequence before after it.
            $Local:FormattedMessage = $Local:FormattedMessage -replace ([Regex]::Escape($PSStyle.Reset)), "$($PSStyle.Reset)$ColourSeq";
            $Local:FormattedMessage = "$ColourSeq$Local:FormattedMessage$($PSStyle.Reset)";
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
    [Parameter(Mandatory, HelpMessage = 'The error records invocation info.', ParameterSetName = 'InvocationInfo')]
    [ValidateNotNullOrEmpty()]
    [System.Management.Automation.InvocationInfo]$InvocationInfo,

    [Parameter(Mandatory, HelpMessage = 'The error record to format.', ParameterSetName = 'ErrorRecord')]
    [ValidateNotNullOrEmpty()]
    [System.Management.Automation.Language.ParseError]$ErrorRecord,

    [Parameter(HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
    [AllowNull()]
    [String]$Message,

    [Parameter(HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
    [ValidateNotNullOrEmpty()]
    [Alias('Prefix')]
    [String]$UnicodePrefix,

    [Parameter(HelpMessage = 'Return the formatted message instead of writing it to the console.')]
    [Switch]$PassThru,

    [Int]$PreviewExtraLines = 5
) {
    $Rows = [ordered]@{
        File = @{
            Value = $null;
        }
        Where = @{
            Value = $null
        }
        Preview = @{
            Value = $null;
            Statement = $null;
            StatementLine = 0;
        }
    }
    $Padding = ($Rows.GetEnumerator() | ForEach-Object {
        if ($null -eq $_.Value.Name) {
            $_.Value.Name = $_.Key;
        }

        $_.Value.Name.Length;
    } | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum) + 1;

    if ($PSCmdlet.ParameterSetName -eq 'InvocationInfo') {
        $Line = $InvocationInfo.Line | ForEach-Object { $_.Trim() };
        if ($InvocationInfo.ScriptName) { $Rows.File.Value = (Format-TrimToConsoleWidth -Line $InvocationInfo.ScriptName -TrimType Left -Padding $Padding).String; }

        if ($InvocationInfo.Statement) {
            $Statement = $InvocationInfo.Statement;
            # FIXME - Don't do it this way
            $StatementIndex = $Line.IndexOf($Statement);

            # FIXME: This is a hack to fix the issue where the statement index is -1, this shouldn't happen!
            if ($StatementIndex -lt 0) {
                $StatementIndex = 0;
            }
        } else {
            $StatementIndex = 0;
            $Statement = $Line;
        }

        $Padding = $Padding # + ($EllipsisLength * 2);
        $ConsoleWidth = $Host.UI.RawUI.BufferSize.Width - $Padding;
        $FileStream = [System.IO.File]::OpenRead($InvocationInfo.ScriptName);
        [System.IO.StreamReader]$StreamReader = [System.IO.StreamReader]::new($FileStream);
        # TODO - Don't have to read the whole file to find this.
        $Content = $StreamReader.ReadToEnd();
        $StatementIndex = $Content.IndexOf($Statement);

        $Result = Get-SurroundingContext `
            -Statement $Statement `
            -StreamReader $StreamReader `
            -FocusRange ([Tuple]::Create($StatementIndex, ($StatementIndex + $Statement.Length))) `
            -MaxLineLength $ConsoleWidth;
        $String = [String]::new($Result.Buffer);

        $StreamReader.Close();
        $FileStream.Close();

        $Position = Get-Position -String $String -Search $Statement;
        $Rows.Preview.StatementIndex = $Position.Start;
        $Rows.Preview.StatementLine = $Position.StartLine;
        $Rows.Preview.Statement = $Statement;

        $Rows.Preview.Value = (Format-ColourAt `
            -String $String `
            -StartIndex $Rows.Preview.StatementIndex `
            -EndIndex ($Rows.Preview.StatementIndex + $Rows.Preview.Statement.Length) `
            -ColourSequence $PSStyle.Foreground.Red);

        $Rows.Where.Value = Format-WherePosition `
            -StartLine $InvocationInfo.ScriptLineNumber `
            -StartColumn $InvocationInfo.OffsetInLine `
            -EndLine ($InvocationInfo.ScriptLineNumber + $Position.EndLine) `
            -EndColumn $Position.EndColumn;
    } else {
        $Message = $ErrorRecord.Message;
        $Rows.File.Value = (Format-TrimToConsoleWidth -Line $ErrorRecord.Extent.File -TrimType Left -Padding $Padding).String;
        $Rows.Where.Value = Format-WherePosition `
            -StartLine $ErrorRecord.Extent.StartLineNumber `
            -EndLine $ErrorRecord.Extent.EndLineNumber `
            -StartColumn $ErrorRecord.Extent.StartColumnNumber `
            -EndColumn $ErrorRecord.Extent.EndColumnNumber;
        $Statement = $ErrorRecord.Extent.Text;

        $Colour = $PSStyle.Foreground.Red;
        $Reset = $PSStyle.Reset;

        $ConsoleWidth = $Host.UI.RawUI.BufferSize.Width - $Padding;
        $StatementLength = $Statement.Length;
        $ContextFromEachSide = [Math]::Floor(($Local:ConsoleWidth - $Statement.Length) / 2);
        if ($ErrorRecord.Extent.File -and $ContextFromEachSide -gt 0) {
            $FileStream = [System.IO.File]::OpenRead($ErrorRecord.Extent.File);
            [System.IO.StreamReader]$StreamReader = [System.IO.StreamReader]::new($FileStream);

            $Buffer = New-Object char[] (($Local:ConsoleWidth * ($PreviewExtraLines * 2)) + $Colour.Length + $Reset.Length);
            $StartOffset = $ErrorRecord.Extent.StartOffset;

            $Backwards = Get-WalkedBuffer `
                -StreamReader $StreamReader `
                -StartOffset $StartOffset `
                -Direction Backward `
                -MaxLineLength $Local:ConsoleWidth `
                -MaxLines ([Math]::Ceiling($PreviewExtraLines / 2));
            $Rows.Preview.StatementLine = $Backwards.LinesAdded;
            $Offset = $Backwards.Buffer.Length;
            for ($i = 0; $i -lt $Backwards.Buffer.Length; $i++) {
                $Buffer[$i] = $Backwards.Buffer[$i];
            }

            for ($i = 0; $i -lt $Colour.Length; $i++) { $Buffer[$Local:Offset + $i] = $Colour[$i]; }
            $StatementLength += $Colour.Length;

            $StatementIndex = $Offset
            for ($i = $StatementIndex; $i -le $StatementIndex + $Statement.Length; $i++) {
                $BufferIndex = $i + $Colour.Length;
                $TempBufferIndex = $i - $Offset;
                $Buffer[$BufferIndex] = $Statement[$TempBufferIndex];
            }

            for ($i = 0; $i -lt $Reset.Length; $i++) { $Buffer[$Local:StatementIndex + $Local:StatementLength + $i] = $Reset[$i]; }
            $StatementLength += $Reset.Length;

            $Forward = Get-WalkedBuffer `
                -StreamReader $StreamReader `
                -StartOffset ($StartOffset + $Statement.Length) `
                -Direction Forward `
                -MaxLineLength $Local:ConsoleWidth `
                -MaxLines ([Math]::Floor($PreviewExtraLines / 2));
            for ($i = 0; $i -lt $Forward.Buffer.Length; $i++) {
                $Buffer[$StatementIndex + $StatementLength + $i] = $Forward.Buffer[$i];
            }

            $StreamReader.Close();
            $FileStream.Close();

            $FormatResult = Format-TrimKeepingMultilineIndent -String ([String]::new($Buffer));
            $Rows.Preview.Value = $FormatResult.String;
            $Rows.Preview.Statement = $Statement;
            $Rows.Preview.StatementIndex = $ErrorRecord.Extent.StartColumnNumber - 1 - $FormatResult.Indent;
        } else {
            $StatementIndex = 0;
            $Rows.Preview.Value = $Statement;
        }
    }

    [System.Collections.Generic.List[String]]$PreviewLines = ($Rows.Preview.Value -split "`n") | Where-Object { -not [String]::IsNullOrWhiteSpace($_) };
    $Highlight = Format-ColourAndReset (
        (' ' * ($Rows.Preview.StatementIndex)) +
        ('^' * [Math]::Max(1, [Math]::Min($Rows.Preview.Statement.Length, $ConsoleWidth - $Rows.Preview.StatementIndex - 2)))
    ) $PSStyle.Foreground.Red;
    if (-not [String]::IsNullOrWhiteSpace($Message)) {
        $Message = Format-ColourAndReset ((' ' * $Rows.Preview.StatementIndex) + $Message) $PSStyle.Foreground.Red;
        $Message = $Message -replace "\. ", "`n"; # FIXME - Seems to be ok to split messages by sentances but needs a more robust implementation.
    }
    $LineOffset = $Rows.Preview.StatementLine;
    if ($Rows.Preview.StatementLine -eq ($PreviewLines.Count - 1)) {
        $PreviewLines += $Highlight;
        if ($Message) { $PreviewLines += $Message; }
    } else {
        Invoke-Info "Inserting Highlight at $LineOffset in $($PreviewLines.Count) lines.";
        $PreviewLines.Insert($LineOffset, $Highlight);
        if ($Message) { $PreviewLines.Insert($LineOffset + 1, $Message); }
    }
    $Rows.Preview.Value = $PreviewLines -join "`n";

    # Fucking PS 5 doesn't allow variable overrides so i have to add the colour to all of them. :<(
    [HashTable]$Private:BaseArgs = @{
        PSPrefix        = if ($UnicodePrefix) { $UnicodePrefix } else { $null };
        ShouldWrite     = $True;
        PassThru        = $PassThru;
        MultiLineIndent = $Padding;
    };

    if (-not $Rows.File.Value) { $Rows.File.Value = 'Unknown'; }
    $Rows.File.Value = Format-ColourAndReset $Rows.File.Value $PSStyle.Foreground.Red;
    $Rows.Where.Value = Format-ColourAndReset $Rows.Where.Value $PSStyle.Foreground.Red;

    $Rows.Keys | ForEach-Object {
        $Value = $Rows[$_].Value;
        $Row = $Rows[$_].Name;

        if ($null -eq $Value -or [String]::IsNullOrEmpty($Value)) {
            Invoke-Debug "Skipping row $Row as it has no value.";
            return;
        }

        $Prefix = Format-ColourAndReset "$Row$(' ' * ($Padding - $Row.Length))|" $PSStyle.Foreground.Cyan;
        Invoke-Write @Private:BaseArgs -PSMessage "$Prefix $Value" -PSColour White;
    }
}

#region Logging at Level Functions

<#
.SYNOPSIS
    Writes a message to the console at the Verbose level if the VerbosePreference is not SilentlyContinue or Ignore.

.PARAMETER InputObject
    A hashtable of parameters to be splatted into Invoke-Verbose. When passed, all other parameters are ignored.

.PARAMETER Message
    The message to write to the console.

.PARAMETER UnicodePrefix
    The Unicode Prefix to use if the terminal supports Unicode.

.PARAMETER PassThru
    Return the formatted message instead of writing it to the console.
#>
function Invoke-Verbose {
    [CmdletBinding(PositionalBinding, DefaultParameterSetName = 'Splat')]
    param(
        [Parameter(ParameterSetName = 'InputObject', Position = 0, ValueFromPipeline)]
        [HashTable]$InputObject,

        [Parameter(ParameterSetName = 'Splat', Position = 0, ValueFromPipelineByPropertyName, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Message,

        [Parameter(ParameterSetName = 'Splat', Position = 1, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('Prefix')]
        [String]$UnicodePrefix,

        [Parameter(ValueFromPipelineByPropertyName)]
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

<#
.SYNOPSIS
    Writes a message to the console at the Debug level if the DebugPreference is not SilentlyContinue or Ignore.

.PARAMETER InputObject
    A hashtable of parameters to be splatted into Invoke-Debug. When passed, all other parameters are ignored.

.PARAMETER Message
    The message to write to the console.

.PARAMETER UnicodePrefix
    The Unicode Prefix to use if the terminal supports Unicode.

.PARAMETER PassThru
    Return the formatted message instead of writing it to the console.
#>
function Invoke-Debug {
    [CmdletBinding(PositionalBinding, DefaultParameterSetName = 'Splat')]
    param(
        [Parameter(ParameterSetName = 'InputObject', Position = 0, ValueFromPipeline)]
        [HashTable]$InputObject,

        [Parameter(ParameterSetName = 'Splat', Position = 0, ValueFromPipelineByPropertyName, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Message,

        [Parameter(ParameterSetName = 'Splat', Position = 1, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('Prefix')]
        [String]$UnicodePrefix,

        [Parameter(ValueFromPipelineByPropertyName)]
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

<#
.SYNOPSIS
    Writes a message to the console at the Information level if the InformationPreference is not Ignore.

.PARAMETER InputObject
    A hashtable of parameters to be splatted into Invoke-Info. When passed, all other parameters are ignored.

.PARAMETER Message
    The message to write to the console.

.PARAMETER UnicodePrefix
    The Unicode Prefix to use if the terminal supports Unicode.

.PARAMETER PassThru
    Return the formatted message instead of writing it to the console.
#>
function Invoke-Info {
    [CmdletBinding(PositionalBinding, DefaultParameterSetName = 'Splat')]
    param(
        [Parameter(ParameterSetName = 'InputObject', Position = 0, ValueFromPipeline)]
        [HashTable]$InputObject,

        [Parameter(ParameterSetName = 'Splat', Position = 0, ValueFromPipelineByPropertyName, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Message,

        [Parameter(ParameterSetName = 'Splat', Position = 1, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('Prefix')]
        [String]$UnicodePrefix,

        [Parameter(ValueFromPipelineByPropertyName)]
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

<#
.SYNOPSIS
    Writes a message to the console at the Warning level if the WarningPreference is not SilentlyContinue or Ignore.

.PARAMETER InputObject
    A hashtable of parameters to be splatted into Invoke-Warn. When passed, all other parameters are ignored.

.PARAMETER Message
    The message to write to the console.

.PARAMETER UnicodePrefix
    The Unicode Prefix to use if the terminal supports Unicode.

.PARAMETER PassThru
    Return the formatted message instead of writing it to the console.
#>
function Invoke-Warn {
    [CmdletBinding(PositionalBinding, DefaultParameterSetName = 'Splat')]
    param(
        [Parameter(ParameterSetName = 'InputObject', Position = 0, ValueFromPipeline)]
        [HashTable]$InputObject,

        [Parameter(ParameterSetName = 'Splat', Position = 0, ValueFromPipelineByPropertyName, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Message,

        [Parameter(ParameterSetName = 'Splat', Position = 1, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('Prefix')]
        [String]$UnicodePrefix,

        [Parameter(ValueFromPipelineByPropertyName)]
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

<#
.SYNOPSIS
    Writes a message to the console at the Error level if the ErrorPreference is not SilentlyContinue or Ignore.

.PARAMETER InputObject
    A hashtable of parameters to be splatted into Invoke-Error. When passed, all other parameters are ignored.

.PARAMETER Message
    The message to write to the console.

.PARAMETER UnicodePrefix
    The Unicode Prefix to use if the terminal supports Unicode.

.PARAMETER PassThru
    Return the formatted message instead of writing it to the console.

.PARAMETER Throw
    If this is a terminating error and should be thrown.

.PARAMETER ErrorCategory
    The error category to use when throwing an error.
#>
function Invoke-Error {
    [CmdletBinding(PositionalBinding, DefaultParameterSetName = 'Splat')]
    param(
        [Parameter(ParameterSetName = 'InputObject', Position = 0, ValueFromPipeline)]
        [HashTable]$InputObject,

        [Parameter(ParameterSetName = 'Splat', Position = 0, ValueFromPipelineByPropertyName, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Message,

        [Parameter(ParameterSetName = 'Splat', Position = 1, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('Prefix')]
        [String]$UnicodePrefix,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Switch]$PassThru,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Switch]$Throw,

        [Parameter(ValueFromPipelineByPropertyName)]
        [System.Management.Automation.ErrorCategory]$ErrorCategory = [System.Management.Automation.ErrorCategory]::NotSpecified,

        [Parameter(DontShow, ValueFromPipelineByPropertyName)]
        [System.Management.Automation.InvocationInfo]$Caller = (Get-PSCallStack)[0].InvocationInfo,

        [Parameter(DontShow, ValueFromPipelineByPropertyName)]
        [System.Management.Automation.PSCmdlet]$CallerCmdlet = $PSCmdlet
    )

    process {
        if ($InputObject) {
            Invoke-Error @InputObject;
            return;
        }

        if (-not $Throw) {
            $Local:Params = @{
                PSPrefix    = if ($UnicodePrefix) { $UnicodePrefix } else { '❌' };
                PSMessage   = $Message;
                PSColour    = 'Red';
                ShouldWrite = $PSCmdlet.GetVariableValue('ErrorActionPreference') -notmatch 'SilentlyContinue|Ignore';
                PassThru    = $PassThru;
            };

            Invoke-Write @Local:Params;
        }

        if ($Throw) {
            $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new($Message),
                'Error',
                $ErrorCategory,
                $Caller
            );

            $Cmdlet = if ($CallerCmdlet) { $CallerCmdlet } else { $PSCmdlet; }
            $Cmdlet.ThrowTerminatingError($ErrorRecord);
        }
    }
}
#endregion

<#
.SYNOPSIS
    Invokes a ScriptBlock with a timeout, optionally allowing the user to cancel the timeout.

.PARAMETER Timeout
    The timeout in milliseconds.

.PARAMETER Activity
    The message to write to the console.

.PARAMETER StatusMessage
    The format string to use when writing the status message, must contain a single placeholder for the time left in seconds.

.PARAMETER TimeoutScript
    The ScriptBlock to invoke if timeout is reached and wasn't cancelled.

.PARAMETER CancelScript
    The ScriptBlock to invoke if timeout was cancelled.

.PARAMETER AllowCancel
    If the timeout is cancellable.
#>
function Invoke-Timeout {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Int]$Timeout,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Activity,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$StatusMessage,

        [Parameter()]
        [ScriptBlock]$TimeoutScript,

        [Parameter(ParameterSetName = 'Cancellable')]
        [ScriptBlock]$CancelScript,

        [Parameter(ParameterSetName = 'Cancellable')]
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

<#
.SYNOPSIS
    Invokes a ScriptBlock with a progress bar.

.PARAMETER Id
    The ID of the progress bar, used to display multiple progress bars at once.

.PARAMETER Activity
    The activity to display in the progress bar.

.PARAMETER Status
    The status message to display in the progress bar.
    This is formatted with three placeholders:
        The current completion percentage.
        The index of the item being processed.
        The total number of items being processed.

.PARAMETER Get
    The ScriptBlock which returns the items to process.

.PARAMETER Process
    The ScriptBlock to process each item.

.PARAMETER Format
    The ScriptBlock that formats the items name for the progress bar.
    If left empty, the ToString method is used.

.PARAMETER FailedProcessItem
    The ScriptBlock to invoke when an item fails to process.
#>
function Invoke-Progress {
    Param(
        [Parameter()]
        [Int]$Id = 0,

        [Parameter()]
        [String]$Activity,

        [Parameter()]
        [String]$Status,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [ScriptBlock]$Get,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [ScriptBlock]$Process,

        [Parameter()]
        [ValidateNotNull()]
        [ScriptBlock]$Format = { $_.ToString() },

        [Parameter()]
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

#region Utility Functions
function Format-ColourAndReset {
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory)]
        [String]$String,

        [Parameter(Mandatory)]
        [String]$ColourSequence
    )

    if ([String]::IsNullOrEmpty($String)) {
        return $null;
    }

    return "$ColourSequence$String$($PSStyle.Reset)";
}

function Format-ColourAt {
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory)]
        [String]$String,

        [Parameter(Mandatory)]
        [Int]$StartIndex,

        [Parameter(Mandatory)]
        [Int]$EndIndex,

        [Parameter(Mandatory)]
        [String]$ColourSequence
    )

    if ([String]::IsNullOrEmpty($String)) {
        return $null;
    }

    try {
        $ThrowArgs = @{
            Throw = $True;
            ErrorCategory = [System.Management.Automation.ErrorCategory]::InvalidArgument;
            Caller = $PSCmdlet.MyInvocation;
            CallerCmdlet = $PSCmdlet;
        }

        if ($StartIndex -lt 0) { Invoke-Error 'StartIndex cannot be less than 0.' @ThrowArgs; }
        if ($EndIndex -gt $String.Length) { Invoke-Error "EndIndex{$EndIndex} cannot be greater than the length{$($String.Length)} of the string." @ThrowArgs; }
        if ($StartIndex -gt $EndIndex) { Invoke-Error 'StartIndex cannot be greater than EndIndex.' @ThrowArgs; }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_);
    }

    $Before = $String.Substring(0, $StartIndex);
    $Content = $String.Substring($StartIndex, $EndIndex - $StartIndex);
    $After = $String.Substring($EndIndex);

    return "$Before$ColourSequence$Content$($PSStyle.Reset)$After";
}

function Format-RemoveEmptyLine {
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory)]
        [String]$String,

        [Parameter()]
        [Switch]$RemoveFinalNewLine
    )

    if ([String]::IsNullOrEmpty($String)) {
        return $null;
    }

    for ($i = 0; $i -lt $String.Length; $i++) {
        $Char = $String[$i];
        if ($Char -eq "`n" -and ($Char -eq "`n" -or ($RemoveFinalNewLine -and $i -eq ($String.Length - 1)))) {
            $String = $String.Remove($i, 1);
            $i--;
        }
    }

    return $String;
}

function Format-TrimToConsoleWidth {
    [CmdletBinding()]
    [OutputType({[PSCustomObject]@{
        String      = [String];
        FocusRange  = [Int];
    }})]
    param(
        [Parameter(Mandatory)]
        [String]$Line,

        [Parameter(Mandatory)]
        [ValidateSet('Left', 'Right', 'Both')]
        [String]$TrimType,

        [Parameter(HelpMessage = '
            A range within the line that should not be touched while trimming.
            Note that this can prevent the line from being trimmed to the console width if the range is too large.
        ')]
        [Tuple[int,int]]$EnsureKeeping,

        [Parameter()]
        [Int]$Padding = 0,

        [Parameter(DontShow)]
        [Int]$EllipsisLength = 3
    )

    $Padding = $Padding + ($EllipsisLength * 2);
    $ConsoleWidth = $Host.UI.RawUI.BufferSize.Width - $Padding;

    $Line = (Format-TrimKeepingMultilineIndent -String $Line -TrimType Both).String;
    if ($Line.Length -le $ConsoleWidth) {
        return [PSCustomObject]@{
            String = $Line;
            KeepStartIndex = $EnsureKeeping.Item1;
        };
    }

    $TrimLength = $Line.Length - $Local:ConsoleWidth;
    if ($TrimType -eq 'Left') {
        $LeftSide = $TrimLength;
    } elseif ($TrimType -eq 'Right') {
        $RightSide = $TrimLength;
    } elseif ($TrimType -eq 'Both') {
        $LeftSide = [System.Math]::Ceiling($TrimLength / 2);
        $RightSide = [System.Math]::Floor($TrimLength / 2);
    }

    if ($EnsureKeeping) {
        $SpareSpace = 0;
        do {
            $LeftWithKeep = [Math]::Min($LeftSide, $EnsureKeeping.Item1);
            $RightWithKeep = [Math]::Min($RightSide, $Line.Length - $EnsureKeeping.Item2);
            $SpareSpace += ($LeftSide - $LeftWithKeep) + ($RightSide - $RightWithKeep);

            $LeftSide = $LeftWithKeep;
            $RightSide = $RightWithKeep;

            if ($LeftSide -ne $EnsureKeeping.Item1) {
                $CanFill = $EnsureKeeping.Item1 - $LeftSide;
                $AmountToFill = [Math]::Min($SpareSpace, $CanFill);
                $LeftSide += $AmountToFill;
                $SpareSpace -= $AmountToFill;
            }

            if ($RightSide -ne $Line.Length - $EnsureKeeping.Item2) {
                $CanFill = ($Line.Length - $EnsureKeeping.Item2) - $RightSide;
                $AmountToFill = [Math]::Min($SpareSpace, $CanFill);
                $RightSide += $AmountToFill;
                $SpareSpace -= $AmountToFill;
            }

            # If we can't fill any more space then break.
            if ($LeftSide -eq $EnsureKeeping.Item1 -and $RightSide -eq $Line.Length - $EnsureKeeping.Item2) {
                break;
            }
        } while ($SpareSpace -ne 0);

        $LeftWithKeep = [Math]::Min($LeftSide, $EnsureKeeping.Item1);
        $RightWithKeep = [Math]::Min($RightSide, $Line.Length - $EnsureKeeping.Item2);

        $LeftSide = [Math]::Min($LeftSide, $EnsureKeeping.Item1);
        $RightSide = [Math]::Min($RightSide, $Line.Length - $EnsureKeeping.Item2);
    }

    if ($TrimType -eq 'Both') {
        $GreaterSide;
        $LesserSide;
        if ($LeftSide -ge $RightSide) {
            $GreaterSide = $LeftSide;
            $LesserSide = $RightSide;
        } else {
            $GreaterSide = $RightSide;
            $LesserSide = $LeftSide;
        };
        $Difference = [Math]::Min($GreaterSide - $LesserSide, $TrimLength);

        $StartIndex = 0;
        $EndIndex = $Line.Length - $Difference;
        if ($GreaterSide -eq $LeftSide) {
            $TrimLength -= $Difference;
            $StartIndex = $Difference;
            $StatementIndex -= $Difference;

            if ($TrimLength -gt 0) {
                $FromEachSide = [Math]::Ceiling($TrimLength / 2);
                $EndIndex -= [Math]::Ceiling($TrimLength / 2);
                $StartIndex += $FromEachSide;
            }
        } else {
            $TrimLength -= $Difference;

            if ($TrimLength -gt 0) {
                $FromEachSide = [System.Math]::Ceiling($TrimLength / 2);
                $EndIndex -= $TrimLength;
                $StartIndex += $FromEachSide;
            }
        }

        $Line = $Line.Substring($StartIndex, $EndIndex);
    } else {
        $Line = if ($TrimType -eq 'Left') {
            $Line.Substring($LeftSide)
        } else {
            $Line.Substring(0, $Line.Length - $RightSide)
        };
    }

    # If either side is trimmed then add the ellipsis.
    if ($StartIndex -gt 0) {
        $Ellipsis = '.' * ([Math]::Min($EllipsisLength, $StartIndex));
        $Line = $Ellipsis + $Line;
        $StartIndex -= $Ellipsis.Length;
        $EndIndex += $Ellipsis.Length;
    }

    if ($EndIndex -lt $Line.Length) {
        $Ellipsis = '.' * ([Math]::Min($EllipsisLength, $Line.Length - $EndIndex));
        $Line = $Line + $Ellipsis;
    }

    return [PSCustomObject]@{
        String = $Line;
        KeepStartIndex = $EnsureKeeping.Item1 - $StartIndex;
    };
}

function Format-TrimKeepingMultilineIndent {
    [CmdletBinding()]
    [OutputType({
        [PSCustomObject]@{
            String = [String];
            FromStart = [Int];
            FromEnd = [Int];
        }
    })]
    param(
        [Parameter(Mandatory, Position = 0)]
        [String]$String,

        [Parameter(Position = 1)]
        [ValidateSet('Start', 'End', 'Both')]
        [String]$TrimType = 'Both'
    )

    $Lines = $String -split "`n";
    $Lines = $Lines | Where-Object { $_ -notmatch '^\s*$' };
    $TrimStart = $Lines | ForEach-Object { $_.IndexOf($_.TrimStart()) } | Measure-Object -Minimum | Select-Object -ExpandProperty Minimum;

    if ($TrimType -eq 'Start' -or $TrimType -eq 'Both') {
        $Lines = $Lines | ForEach-Object { $_.Substring($TrimStart) };
    }

    $FromEnd = 0;
    if ($TrimType -eq 'End' -or $TrimType -eq 'Both') {
        $Lines = $Lines | ForEach-Object {
            $Trim = $_.TrimEnd();
            $FromEnd += $_.Length - $Trim.Length;
            $Trim
        };
    }

    return [PSCustomObject]@{
        String   = $Lines -join "`n";
        FromStart = $TrimStart;
        FromEnd   = $FromEnd;
    }
}

function Format-WherePosition {
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Int]$StartLine,
        [Int]$EndLine,
        [Int]$StartColumn,
        [Int]$EndColumn
    )

    $SB = New-Object System.Text.StringBuilder;
    if ($StartLine) {
        $null = $SB.Append($StartLine);
    }

    if ($StartColumn) {
        $null = $SB.Append("[$StartColumn");
    }

    if ($EndLine -ne $StartLine) {
        $null = $SB.Append("]..$EndLine");
        if ($EndColumn) { $null = $SB.Append("[$EndColumn]"); }
    } elseif ($EndColumn -ne $StartColumn) {
        $null = $SB.Append("..$EndColumn]");
    } elseif ($StartColumn) {
        $null = $SB.Append("]");
    } elseif ($EndColumn) {
        $null = $SB.Append("[$EndColumn]");
    }

    return $SB.ToString();
}

function Get-WalkedBuffer {
    [CmdletBinding()]
    [OutputType({[PSCustomObject]@{
        Buffer = [Char[]];
        Offset = [Int];
        LinesAdded = [Int];
    }})]
    param(
        [Parameter(Mandatory)]
        [System.IO.StreamReader]$StreamReader,

        [Parameter(Mandatory)]
        [Int]$StartOffset,

        [Parameter(Mandatory)]
        [ValidateSet('Forward', 'Backward')]
        [String]$Direction,

        [Parameter(Mandatory)]
        [Int]$MaxLineLength,

        [Parameter(Mandatory)]
        [Int]$MaxLines
    )

    $null = $StreamReader.BaseStream.Seek($StartOffset, [System.IO.SeekOrigin]::Begin);
    $StreamReader.DiscardBufferedData();

    $Buffer = New-Object char[] ($MaxLineLength * $MaxLines);
    $Offset = 0;
    $LineCount = 0;
    $ActiveLineLength = 0;
    while ($ActiveLineLength -lt $MaxLineLength -and $StreamReader.BaseStream.Position -gt 0 -and $StreamReader.BaseStream.Position -lt $StreamReader.BaseStream.Length) {
        $NextPosition = if ($Direction -eq 'Forward') { $StartOffset + $Offset } else { $StartOffset - $Offset };
        $null = $StreamReader.BaseStream.Seek($NextPosition, [System.IO.SeekOrigin]::Begin);
        $StreamReader.DiscardBufferedData();

        $null = $StreamReader.Read($Buffer, $Offset, 1);
        [Char]$Char = $Buffer[$Offset];

        if ($Char -eq "`r`n" -or $Char -eq "`n") {
            if ($LineCount -eq $MaxLines) {
                $Offset--;
                break;
            }

            $ActiveLineLength = 0;
            # If the start offset lands on a newline it can mess up the line count.
            if ($Offset -gt 0) { $LineCount++; }
        }

        $Offset++;
        $ActiveLineLength++;
    }

    $Buffer = $Buffer[0..$Offset];
    if ($Direction -eq 'Backward') {
        $ReverseBuffer = New-Object char[] $Offset;
        for ($i = 0; $i -lt $Offset; $i++) {
            $ReverseBuffer[$i] = $Buffer[$Offset - $i];
        }

        $Buffer = $ReverseBuffer;
    }

    return [PSCustomObject]@{
        Buffer     = $Buffer;
        Offset     = $Offset;
        LinesAdded = $LineCount;
    }
}

function Get-SurroundingContext {
    [CmdletBinding()]
    [OutputType({[PSCustomObject]@{
        Buffer = [Char[]];
        FocusRange = [Tuple[int,int]];
        FocusLine = [Tuple[int,int]];
    }})]
    param(
        [Parameter(Mandatory)]
        [String]$Statement,

        [Parameter(Mandatory)]
        [Tuple[int,int]]$FocusRange,

        [Parameter(Mandatory)]
        [System.IO.StreamReader]$StreamReader,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [Int]$MaxLineLength,

        [Parameter()]
        [ValidateNotNull()]
        [Int]$PreviewExtraLines = 3
    )

    $Buffer = New-Object Char[] ($MaxLineLength * $PreviewExtraLines);

    $Backward = Get-WalkedBuffer `
        -StreamReader $StreamReader `
        -StartOffset $StartOffset `
        -Direction Backward `
        -MaxLineLength $MaxLineLength `
        -MaxLines ([Math]::Ceiling($PreviewExtraLines / 2));
    $Offset = $Backward.Buffer.Length;
    for ($i = 0; $i -lt $Backward.Buffer.Length; $i++) {
        $Buffer[$i] = $Backward.Buffer[$i];
    }

    for ($i = 0; $i -lt $Colour.Length; $i++) { $Buffer[$Offset + $i] = $Colour[$i]; }
    $StatementLength += $Colour.Length;

    $StatementIndex = $Offset
    for ($i = $StatementIndex; $i -le $StatementIndex + $Statement.Length; $i++) {
        $BufferIndex = $i + $Colour.Length;
        $TempBufferIndex = $i - $Offset;
        $Buffer[$BufferIndex] = $Statement[$TempBufferIndex];
    }

    for ($i = 0; $i -lt $Reset.Length; $i++) { $Buffer[$StatementIndex + $StatementLength + $i] = $Reset[$i]; }
    $StatementLength += $Reset.Length;

    $Forward = Get-WalkedBuffer `
        -StreamReader $StreamReader `
        -StartOffset ($StartOffset + $Statement.Length) `
        -Direction Forward `
        -MaxLineLength $Local:ConsoleWidth `
        -MaxLines ([Math]::Floor($PreviewExtraLines / 2));
    for ($i = 0; $i -lt $Forward.Buffer.Length; $i++) {
        $Buffer[$StatementIndex + $StatementLength + $i] = $Forward.Buffer[$i];
    }

    $Result = [PSCustomObject]@{
        Buffer = $Buffer;
        FocusRange = [Tuple]::Create(
            $FocusRange.Item1 - $Backward.Offset,
            $FocusRange.Item2 - $Backward.Offset
        );
        FocusLine = [Tuple]::Create(
            $Backward.LinesAdded,
            $Backward.LinesAdded + ($Statement.Split("`n").Count - 1)
        );
    };

    return $Result;
}

function Get-Position {
    [CmdletBinding()]
    [OutputType(ParameterSetName = 'ByLine', [System.Collections.Generic.List[PSCustomObject]])]
    [OutputType(ParameterSetName = 'ByOffset', [PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [String]$String,

        [Parameter(Mandatory, ParameterSetName = 'ByLine')]
        [String]$Search,

        [Parameter(Mandatory, ParameterSetName = 'ByOffset')]
        [Int]$Offset,

        [Parameter()]
        [Int]$Limit = 0
    )

    if ($PSCmdlet.ParameterSetName -eq 'ByLine') {
        $Results = [System.Collections.Generic.List[PSCustomObject]]::new();
        $Found = 0;
        $SearchSplit = $Search.Split("`n");
        $LinesInSearch = $SearchSplit.Count;
        $RemovedLines = 0;
        do {
            $Index = $String.IndexOf($Search);
            if ($Index -lt 0) { break; }

            $Found++;
            $BeforeIndex = $String.Substring(0, $Index);
            $Split = $BeforeIndex.Split("`n");
            $Results.Add([PSCustomObject]@{
                StartLine = $Split.Count + $RemovedLines;
                EndLine = $Split.Count + $RemovedLines + $LinesInSearch;
                StartColumn = $Split[-1].Length;
                EndColumn = $Split[-1].Length + $SearchSplit[-1].Length
            });

            $String = $String.Substring($Index + $Search.Length);
            $RemovedLines += $Split.Count - $LinesInSearch;
        } while ($Limit -eq 0 -or $Found -lt $Limit);

        return $Results;
    }

    if ($PSCmdlet.ParameterSetName -eq 'ByOffset') {
        $Split = $String.Substring(0, $Offset + 1).Split("`n");

        return [PSCustomObject]@{
            Line = $Split.Count;
            Column = $Split[-1].Length + 1;
        };
    }
}

function Test-IsNableRunner {
    $WindowName = $Host.UI.RawUI.WindowTitle;
    if (-not $WindowName) { return $False; };
    return ($WindowName | Split-Path -Leaf) -eq 'fmplugin.exe';
}

function Test-SupportsUnicode {
    $null -ne $env:WT_SESSION -and -not (Test-IsNableRunner);
}

function Test-SupportsColour {
    -not (Test-IsNableRunner);
}
#endregion

Export-ModuleMember -Function Invoke-Write, Invoke-Verbose, Invoke-Debug, Invoke-Info, Invoke-Warn, Invoke-Error, Format-Error, Invoke-Timeout, Invoke-Progress;
