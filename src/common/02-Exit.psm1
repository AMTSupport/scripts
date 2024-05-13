[HashTable]$Global:ExitHandlers = @{};
[HashTable]$Global:ExitCodes = @{};
[Boolean]$Global:ExitHandlersRun = $false;

function Invoke-Handlers([switch]$IsFailure) {
    if ($Global:ExitHandlersRun) {
        Invoke-Debug -Message 'Exit handlers already run, skipping...';
        return;
    }

    foreach ($Local:ExitHandlerName in $Global:ExitHandlers.Keys) {
        [PSCustomObject]$Local:ExitHandler = $Global:ExitHandlers[$Local:ExitHandlerName];
        if ($Local:ExitHandler.OnlyFailure -and (-not $IsFailure)) {
            continue;
        }

        Invoke-Debug -Message "Invoking exit handler '$Local:ExitHandlerName'...";
        try {
            Invoke-Command -ScriptBlock $Local:ExitHandler.Script;
        }
        catch {
            Invoke-Warn "Failed to invoke exit handler '$Local:ExitHandlerName': $_";
        }
    }

    $Global:ExitHandlersRun = $true;
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
        [String[]]$FormatArgs,

        [Parameter(DontShow)]
        [System.Management.Automation.Cmdlet]$CallingCmdlet = $PSCmdlet
    )

    [String]$Local:ExitDescription = $Global:ExitCodes[$ExitCode];
    if ($null -ne $Local:ExitDescription -and $Local:ExitDescription.Length -gt 0) {
        if ($FormatArgs) {
            [String]$Local:ExitDescription = $Local:ExitDescription -f $FormatArgs;
        }

        Invoke-Error $Local:ExitDescription;
    }
    elseif ($ExitCode -ne 0 -and $ExitCode -ne 9999) {
        Invoke-Warn "No exit description found for code '$ExitCode'";
    }
    elseif ($ExitCode -lt 1000) {
        Invoke-FailedExit -ExitCode $Script:INVALID_ERROR_CODE -FormatArgs $ExitCode;
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
        }
        elseif ($Local:DeepestMessage) {
            Invoke-Error -Message $Local:DeepestMessage;
        }
    }

    Invoke-Handlers -IsFailure:($ExitCode -ne 0);
    if (-not $DontExit) {
        if (-not $Local:DeepestException) {
            [System.Exception]$Local:DeepestException = [System.Exception]::new('Failed Exit');
        }

        if ($null -eq $Local:DeepestException.ErrorRecord.CategoryInfo.Category) {
            [System.Management.Automation.ErrorCategory]$Local:Catagory = [System.Management.Automation.ErrorCategory]::NotSpecified;
        }
        else {
            [System.Management.Automation.ErrorCategory]$Local:Catagory = $Local:DeepestException.ErrorRecord.CategoryInfo.Category;
        }

        [System.Management.Automation.ErrorRecord]$Local:ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]$Local:DeepestException,
            'FailedExit',
            $Local:Catagory,
            $ExitCode
        );

        if ($Local:DeepestException.ErrorRecord) {
            $Global:Error.Add($ErrorRecord);
            $Global:Error.Add($Local:DeepestException.ErrorRecord);
        }

        $CallingCmdlet.ThrowTerminatingError($Local:ErrorRecord);
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

    if ($Global:ExitHandlers[$Local:TrimmedName]) {
        Invoke-Warn "Exit handler '$Local:TrimmedName' already registered, overwriting...";
        $Global:ExitHandlers[$Local:TrimmedName] = $Local:Value;
    }
    else {
        $Global:ExitHandlers.add($Local:TrimmedName, $Local:Value);
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
    $Local:ExitCode = $Global:ExitCodes | Where-Object { $_.Value -eq $Local:TrimmedDescription };
    if (-not $Local:ExitCode) {
        $Local:ExitCode = $Global:ExitCodes.Count + 1001;

        Invoke-Debug "Registering exit code '$Local:ExitCode' with description '$Local:TrimmedDescription'...";
        $Global:ExitCodes.add($Local:ExitCode, $Local:TrimmedDescription);
    }

    return $Local:ExitCode;
}

$Script:INVALID_ERROR_CODE = Register-ExitCode -Description 'Invalid error code {0}, codes must be greater than 1000';

Export-ModuleMember -Function Invoke-Handlers, Invoke-FailedExit, Invoke-QuickExit, Register-ExitHandler, Register-ExitCode, Restart-Script;
