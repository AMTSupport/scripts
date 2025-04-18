Using module .\Logging.psm1

[HashTable]$Script:ExitHandlers = @{};
[HashTable]$Script:ExitCodes = @{};
[Boolean]$Script:ExitHandlersRun = $false;

function Invoke-Handlers([switch]$IsFailure) {
    if ($Script:ExitHandlersRun) {
        Invoke-Debug -Message 'Exit handlers already run, skipping...';
        return;
    }

    foreach ($Local:ExitHandlerName in $Script:ExitHandlers.Keys) {
        [PSCustomObject]$Local:ExitHandler = $Script:ExitHandlers[$Local:ExitHandlerName];
        if ($Local:ExitHandler.OnlyFailure -and (-not $IsFailure)) {
            continue;
        }

        Invoke-Debug -Message "Invoking exit handler '$Local:ExitHandlerName'...";
        try {
            Invoke-Command -ScriptBlock $Local:ExitHandler.Script;
        } catch {
            Invoke-Warn "Failed to invoke exit handler '$Local:ExitHandlerName': $_";
        }
    }

    $Script:ExitHandlersRun = $true;
}

function Invoke-FailedExit {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, HelpMessage = 'The exit code to return.')]
        [ValidateNotNullOrEmpty()]
        [Int]$ExitCode,

        [Parameter(HelpMessage = 'The error record that caused the exit, if any.')]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Switch]$DontExit,

        [Parameter()]
        [String[]]$FormatArgs
    )

    [String]$ExitDescription = $Script:ExitCodes[$ExitCode];
    if (-not [String]::IsNullOrEmpty($ExitDescription)) {
        if ($FormatArgs) { $ExitDescription = $ExitDescription -f $FormatArgs }

        Invoke-Error $ExitDescription;
    } elseif ($ExitCode -ne 0 -and $ExitCode -ne 9999) {
        $Category = [Enum]::ToObject([System.Management.Automation.ErrorCategory], 1)
        Invoke-Error -Message "Exit code $Category";
    }

    # FIXME - Not getting to correct depth of exception
    if ($ErrorRecord) {
        [System.Exception]$Local:DeepestException = $ErrorRecord.Exception;
        [String]$Local:DeepestMessage = $Local:DeepestException.Message;
        [System.Management.Automation.InvocationInfo]$Local:DeepestInvocationInfo = $ErrorRecord.InvocationInfo;

        while ($Local:DeepestException.InnerException) {
            Invoke-Debug "Getting inner exception... (Current: $Local:DeepestException)";
            Invoke-Debug "Inner exception: $($Local:DeepestException.InnerException)";
            if (-not $Local:DeepestException.InnerException.ErrorRecord) {
                Invoke-Debug 'Inner exception has no error record, breaking to keep the current exceptions information...';
                break;
            }

            $Local:DeepestException = $Local:DeepestException.InnerException;

            if ($Local:DeepestException.Message) {
                $Local:DeepestMessage = $Local:DeepestException.Message;
            }

            if ($Local:DeepestException.ErrorRecord.InvocationInfo) {
                $Local:DeepestInvocationInfo = $Local:DeepestException.ErrorRecord.InvocationInfo;
            }
        }

        if ($Local:DeepestInvocationInfo) {
            Format-Error -InvocationInfo $Local:DeepestInvocationInfo -Message $Local:DeepestMessage;
        } elseif ($Local:DeepestMessage) {
            Invoke-Error -Message $Local:DeepestMessage;
        }
    }

    Invoke-Handlers -IsFailure:($ExitCode -ne 0);
    if (-not $DontExit) {
        if (-not $Local:DeepestException) {
            [System.Exception]$Local:DeepestException = [System.Exception]::new('Failed Exit');
        }

        if ($null -eq $Local:DeepestException.ErrorRecord.CategoryInfo.Category) {
            [System.Management.Automation.ErrorCategory]$Local:Category = [System.Management.Automation.ErrorCategory]::NotSpecified;
        } else {
            [System.Management.Automation.ErrorCategory]$Local:Category = $Local:DeepestException.ErrorRecord.CategoryInfo.Category;
        }

        [System.Management.Automation.ErrorRecord]$Local:ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]$Local:DeepestException,
            'FailedExit',
            $Local:Category,
            $ExitCode
        );

        if ($Local:DeepestException.ErrorRecord) {
            $Global:Error.Add($ErrorRecord);
            $Global:Error.Add($Local:DeepestException.ErrorRecord);
        }

        $PSCmdlet.ThrowTerminatingError($Local:ErrorRecord);
    }
}

function Invoke-QuickExit {
    Invoke-Handlers -IsFailure:$False;

    [System.Management.Automation.ErrorRecord]$Local:ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
        [System.Exception]::new('Quick Exit'),
        'QuickExit',
        [System.Management.Automation.ErrorCategory]::NotSpecified,
        $null
    );

    throw $Local:ErrorRecord;
}

function Restart-Script {
    Invoke-Handlers -IsFailure:$False;

    Invoke-Info 'Restarting script...';

    [System.Management.Automation.ErrorRecord]$Local:ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
        [System.Exception]::new('Restart Script'),
        'RestartScript',
        [System.Management.Automation.ErrorCategory]::NotSpecified,
        $null
    );

    throw $Local:ErrorRecord;

}

function Register-ExitHandler {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]$ExitHandler,

        [switch]$OnlyFailure
    )

    [String]$Local:TrimmedName = $Name.Trim();
    [PSCustomObject]$Local:Value = @{ OnlyFailure = $OnlyFailure; Script = $ExitHandler };
    Invoke-Debug "Registering exit handler '$Local:TrimmedName'";

    if ($Script:ExitHandlers[$Local:TrimmedName]) {
        Invoke-Warn "Exit handler '$Local:TrimmedName' already registered, overwriting...";
        $Script:ExitHandlers[$Local:TrimmedName] = $Local:Value;
    } else {
        $Script:ExitHandlers.add($Local:TrimmedName, $Local:Value);
    }
}

function Register-ExitCode {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Description
    )

    $Local:TrimmedDescription = $Description.Trim();
    $Local:ExitCode = $Script:ExitCodes | Where-Object { $_.Value -eq $Local:TrimmedDescription };
    if (-not $Local:ExitCode) {
        $Local:ExitCode = $Script:ExitCodes.Count + 1001;

        Invoke-Debug "Registering exit code '$Local:ExitCode' with description '$Local:TrimmedDescription'...";
        $Script:ExitCodes.add($Local:ExitCode, $Local:TrimmedDescription);
    }

    return $Local:ExitCode;
}

$Script:INVALID_ERROR_CODE = Register-ExitCode -Description 'Invalid error code {}, codes must be greater than 1000';

Export-ModuleMember -Function Invoke-Handlers, Invoke-FailedExit, Invoke-QuickExit, Register-ExitHandler, Register-ExitCode, Restart-Script;
