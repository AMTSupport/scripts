$Private:ExitHandlers = @();

function Invoke-FailedExit {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, HelpMessage = 'The exit code to return.')]
        [ValidateNotNullOrEmpty()]
        [Int]$ExitCode,

        [Parameter(HelpMessage='The error record that caused the exit, if any.')]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    If ($ErrorRecord) {
        [System.Management.Automation.InvocationInfo]$Local:InvocationInfo = $ErrorRecord.InvocationInfo;
        $Local:InvocationInfo | Assert-NotNull -Message "Invocation info was null, how am i meant to find error now??";

        [System.Exception]$Local:RootCause = $ErrorRecord.Exception;
        while ($null -ne $Local:RootCause.InnerException) {
            $Local:RootCause = $Local:RootCause.InnerException;
        }

        Invoke-Error $Local:InvocationInfo.PositionMessage;
        Invoke-Error $Local:RootCause.Message;
    }

    foreach ($Local:ExitHandler in $Private:ExitHandlers) {
        Invoke-Command -ScriptBlock $Local:ExitHandler;
    }

    Exit $ExitCode;
}

function Register-ExitHandler {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]$ExitHandler
    )

    $Private:ExitHandlers += $ExitHandler;
}

Export-ModuleMember -Function Invoke-FailedExit, Register-ExitHandler;
