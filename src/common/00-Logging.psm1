function Local:Get-SupportsUnicode {
    $True
    # $null -ne $env:WT_SESSION;
}

function Invoke-Write {
    [CmdletBinding(PositionalBinding)]
    param (
        [Parameter(ParameterSetName = 'InputObject', ValueFromPipeline)]
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
        [Boolean]$ShouldWrite = $True,

        [Parameter(ParameterSetName = 'Splat', ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Switch]$NoNewLine
    )

    process {
        if ($InputObject) {
            Invoke-Write @InputObject;
            return;
        }

        if (-not $ShouldWrite) {
            return;
        }

        $Local:FormattedMessage = if ($PSMessage.Contains("`n")) {
            $PSMessage -replace "`n", "`n + ";
        } else {
            $PSMessage;
        }

        if (Get-SupportsUnicode -and $PSPrefix) {
            Write-Host -ForegroundColor $PSColour -Object "$PSPrefix $Local:FormattedMessage" -NoNewline:$NoNewLine;
        } else {
            Write-Host -ForegroundColor $PSColour -Object "$Local:FormattedMessage" -NoNewline:$NoNewLine;
        }
    }
}

function Invoke-FormattedError(
    [Parameter(Mandatory, HelpMessage = 'The error records invocation info.')]
    [ValidateNotNullOrEmpty()]
    [System.Management.Automation.InvocationInfo]$InvocationInfo,

    [Parameter(HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
    [ValidateNotNullOrEmpty()]
    [String]$Message,

    [Parameter(HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
    [ValidateNotNullOrEmpty()]
    [Alias('Prefix')]
    [String]$UnicodePrefix
) {
    [String]$Local:TrimmedLine = $InvocationInfo.Line.Trim();
    [String]$Local:Script = $InvocationInfo.ScriptName.Trim();

    if ($InvocationInfo.Statement) {
        [String]$Local:Statement = $InvocationInfo.Statement.Trim();

        # Find where the statement matches in the line, and underline it, indent the statement to where it matches in the line.
        [Int]$Local:StatementIndex = $Local:TrimmedLine.IndexOf($Local:Statement);
    } else {
        [Int]$Local:StatementIndex = 0;
        [String]$Local:Statement = $TrimmedLine;
    }

    [String]$Local:Underline = (' ' * ($Local:StatementIndex + 10)) + ('^' * $Local:Statement.Length);

    # Position the message to the same indent as the statement.
    [String]$Local:Message = if ($null -ne $Message) {
        (' ' * $Local:StatementIndex) + $Message;
    } else { $null };


    # Fucking PS 5 doesn't allow variable overrides so i have to add the colour to all of them. :<(
    [HashTable]$Local:BaseHash = @{
        PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { $null };
        ShouldWrite = $True;
    };

    Invoke-Write @Local:BaseHash -PSMessage "File    | " -PSColour 'Cyan' -NoNewLine;
    Invoke-Write @Local:BaseHash -PSMessage $Local:Script -PSColour 'Red';
    Invoke-Write @Local:BaseHash -PSMessage "Line    | " -PSColour 'Cyan' -NoNewline;
    Invoke-Write @Local:BaseHash -PSMessage $InvocationInfo.ScriptLineNumber -PSColour 'Red';
    Invoke-Write @Local:BaseHash -PSMessage "Preview | " -PSColour 'Cyan' -NoNewLine;
    Invoke-Write @Local:BaseHash -PSMessage $Local:TrimmedLine -PSColour 'Red';
    Invoke-Write @Local:BaseHash -PSMessage "$Local:Underline" -PSColour 'Red';

    if ($Local:Message) {
        Invoke-Write @Local:BaseHash -PSMessage "Message | " -PSColour 'Cyan' -NoNewLine;
        Invoke-Write @Local:BaseHash -PSMessage $Local:Message -PSColour 'Red';
    }
}

function Invoke-Verbose(
    [Parameter(Mandatory, HelpMessage = 'The message to write to the console.')]
    [ValidateNotNullOrEmpty()]
    [String]$Message,

    [Parameter(HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
    [ValidateNotNullOrEmpty()]
    [Alias('Prefix')]
    [String]$UnicodePrefix
) {
    $Local:Params = @{
        PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { '🔍' };
        PSMessage = $Message;
        PSColour = 'Yellow';
        ShouldWrite = $VerbosePreference -ne 'SilentlyContinue';
    };

    Invoke-Write @Local:Params;
}

function Invoke-Debug(
    [Parameter(Mandatory, HelpMessage = 'The message to write to the console.')]
    [ValidateNotNullOrEmpty()]
    [String]$Message,

    [Parameter(HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
    [ValidateNotNullOrEmpty()]
    [Alias('Prefix')]
    [String]$UnicodePrefix
) {
    $Local:Params = @{
        PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { '🐛' };
        PSMessage = $Message;
        PSColour = 'Magenta';
        ShouldWrite = $DebugPreference -ne 'SilentlyContinue';
    };

    Invoke-Write @Local:Params;
}

function Invoke-Info(
    [Parameter(Mandatory, HelpMessage = 'The message to write to the console.')]
    [ValidateNotNullOrEmpty()]
    [String]$Message,

    [Parameter(HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
    [ValidateNotNullOrEmpty()]
    [Alias('Prefix')]
    [String]$UnicodePrefix
) {
    $Local:Params = @{
        PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { 'ℹ️' };
        PSMessage = $Message;
        PSColour = 'Cyan';
        ShouldWrite = $True;
    };

    Invoke-Write @Local:Params;
}

function Invoke-Warn(
    [Parameter(Mandatory, HelpMessage = 'The message to write to the console.')]
    [ValidateNotNullOrEmpty()]
    [String]$Message,

    [Parameter(HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
    [ValidateNotNullOrEmpty()]
    [Alias('Prefix')]
    [String]$UnicodePrefix
) {
    $Local:Params = @{
        PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { '⚠️' };
        PSMessage = $Message;
        PSColour = 'Yellow';
        ShouldWrite = $True;
    };

    Invoke-Write @Local:Params;
}

function Invoke-Error(
    [Parameter(Mandatory, HelpMessage = 'The message to write to the console.')]
    [ValidateNotNullOrEmpty()]
    [String]$Message,

    [Parameter(HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
    [ValidateNotNullOrEmpty()]
    [Alias('Prefix')]
    [String]$UnicodePrefix
) {
    $Local:Params = @{
        PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { '❌' };
        PSMessage = $Message;
        PSColour = 'Red';
        ShouldWrite = $True;
    };

    Invoke-Write @Local:Params;
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

        [Int16]$Local:TimeLeft = $Timeout;
        while ($Local:TimeLeft -gt 0) {
            if ($AllowCancel -and [Console]::KeyAvailable) {
                break;
            }

            Write-Progress `
                -Activity $Activity `
                -Status ($StatusMessage -f ([Math]::Floor($Local:TimeLeft) / 10)) `
                -PercentComplete ($Local:TimeLeft / $Timeout * 100) `
                -Completed:($Local:TimeLeft -eq 1)

            $Local:TimeLeft -= 1;
            Start-Sleep -Milliseconds 1000;
        }

        if ($Local:TimeLeft -eq 0) {
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

Export-ModuleMember -Function Invoke-Write, Invoke-Verbose, Invoke-Debug, Invoke-Info, Invoke-Warn, Invoke-Error, Invoke-FormattedError, Invoke-Timeout;
