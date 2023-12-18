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
        [String]$PSColour
    )

    process {
        if (Get-SupportsUnicode) {
            Write-Host -ForegroundColor $PSColour -Object "$PSPrefix $PSMessage";
        } else {
            Write-Host -ForegroundColor $PSColour -Object "$PSMessage";
        }
    }
}

function Verbose(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Message,
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]$UnicodePrefix
) {
    $Local:Params = @{
        PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { '🔍' };
        PSMessage = $Message;
        PSColour = 'Yellow';
    };

    Invoke-Write @Local:Params;
}

function Debug(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Message,
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]$UnicodePrefix
) {
    $Local:Params = @{
        PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { '🐞' };
        PSMessage = $Message;
        PSColour = 'DarkBlue';
    };

    Invoke-Write @Local:Params;
}

function Info(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Message,
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]$UnicodePrefix
) {
    $Local:Params = @{
        PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { 'ℹ️' };
        PSMessage = $Message;
        PSColour = 'Cyan';
    };

    Invoke-Write @Local:Params;
}

function Warn(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Message,
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]$UnicodePrefix
) {
    $Local:Params = @{
        PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { '⚠️' };
        PSMessage = $Message;
        PSColour = 'Yellow';
    };

    Invoke-Write @Local:Params;
}

function Invoke-Error(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Message,
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]$UnicodePrefix
) {
    $Local:Params = @{
        PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { '❌' };
        PSMessage = $Message;
        PSColour = 'Red';
    };

    Invoke-Write @Local:Params;
}

Export-ModuleMember -Function Verbose, Debug, Info, Warn, Invoke-Error;
