function Local:Get-SupportsUnicode {
    $null -ne $env:WT_SESSION;
}

function Local:Invoke-Write {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String]$PSMessage,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName, HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
        [ValidateNotNullOrEmpty()]
        [String]$PSPrefix,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String]$PSColour,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Boolean]$ShouldWrite
    )

    process {
        # if (-not $ShouldWrite) {
        #     return;
        # }

        $Local:FormattedMessage = if ($PSMessage.Contains("`n")) {
            $PSMessage -replace "`n", "`n + ";
        } else {
            $PSMessage;
        }

        if (Get-SupportsUnicode) {
            Write-Host -ForegroundColor $PSColour -Object "$PSPrefix $Local:FormattedMessage";
        } else {
            Write-Host -ForegroundColor $PSColour -Object "$Local:FormattedMessage";
        }
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
        ShouldWrite = $InformationPreference -ne 'SilentlyContinue';
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
        ShouldWrite = $WarningPreference -ne 'SilentlyContinue';
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
        ShouldWrite = $ErrorActionPreference -ne 'SilentlyContinue';
    };

    Invoke-Write @Local:Params;
}

Export-ModuleMember -Function Invoke-Verbose, Invoke-Debug, Invoke-Info, Invoke-Warn, Invoke-Error;
