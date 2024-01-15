[HashTable]$Global:ExitHandlers = @{};
[HashTable]$Global:ExitCodes = @{};

function Invoke-FailedExit {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, HelpMessage = 'The exit code to return.')]
        [ValidateNotNullOrEmpty()]
        [Int]$ExitCode,

        [Parameter(HelpMessage='The error record that caused the exit, if any.')]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    [String]$Local:ExitDescription = $Global:ExitCodes[$ExitCode];
    if ($Local:ExitDescription) {
        Invoke-Error $Local:ExitDescription;
    }

    if ($ErrorRecord) {
        [System.Exception]$Local:DeepestException = $ErrorRecord.Exception;
        while ($Local:DeepestException.InnerException) {
            Invoke-Debug "Getting inner exception... (Current: $Local:DeepestException)"
            Invoke-Debug "Inner exception: $($Local:DeepestException.InnerException)"
            $Local:DeepestException = $Local:DeepestException.InnerException;
        }

        Invoke-Error $Local:DeepestException.Message;
        Invoke-Error $Local:DeepestException.ErrorRecord.InvocationInfo.PositionMessage;
    }

    foreach ($Local:ExitHandlerName in $Global:ExitHandlers.Keys) {
        [PSCustomObject]$Local:ExitHandler = $Global:ExitHandlers[$Local:ExitHandler];
        if ($Local:ExitHandler.OnlyFailure -and $ExitCode -eq 0) {
            continue;
        }

        Invoke-Debug -Message "Invoking exit handler '$Local:ExitHandlerName'...";
        Invoke-Command -ScriptBlock $Local:ExitHandler.Script;
    }

    Exit $ExitCode;
}

function Invoke-QuickExit {
    foreach ($Local:ExitHandlerName in $Global:ExitHandlers.Keys) {
        [PSCustomObject]$Local:ExitHandler = $Global:ExitHandlers[$Local:ExitHandlerName];
        if ($Local:ExitHandler.OnlyFailure) {
            continue;
        }

        Invoke-Debug -Message "Invoking exit handler '$Local:ExitHandlerName'...";
        Invoke-Command -ScriptBlock $Local:ExitHandler.Script;
    }

    Exit 0;
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
    Invoke-Debug "Registering exit handler '$Local:TrimmedName' with value '$Local:Value'...";

    if ($Global:ExitHandlers[$Local:TrimmedName]) {
        Invoke-Warn "Exit handler '$Local:TrimmedName' already registered, overwriting...";
        $Global:ExitHandlers[$Local:TrimmedName] = $Local:Value;
    } else {
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

Export-ModuleMember -Function Invoke-FailedExit, Invoke-QuickExit, Register-ExitHandler, Register-ExitCode;
