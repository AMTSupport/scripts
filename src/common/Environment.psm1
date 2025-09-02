Using module .\Utils.psm1
Using module .\Logging.psm1
Using module .\Exit.psm1
Using module .\ModuleUtils.psm1

Using namespace System.Management.Automation.Language
Using namespace System.Collections.Generic

[System.Boolean]$Script:ScriptRestarted = $False;
[System.Boolean]$Script:ScriptRestarting = $False;
[System.Collections.Generic.List[String]]$Script:ImportedModules = [System.Collections.Generic.List[String]]::new();
$Script:ModuleSnapshot = Get-Module | Select-Object -ExpandProperty Path | Where-Object {
    # Also Exclude our own modules
    $_ -notmatch '(Environment|Logging|Scope|Utils|Exit).psm1$'
};

#region - Utility Functions
function Local:Get-OrFalse {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [HashTable]$HashTable,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Key
    )

    process {
        if ($HashTable.ContainsKey($Key)) {
            return $HashTable[$Key];
        } else {
            return $false;
        }
    }
}

function Local:Test-IsNableRunner {
    $WindowName = $Host.UI.RawUI.WindowTitle;
    if (-not $WindowName) { return $False; };
    return ($WindowName | Split-Path -Leaf) -eq 'fmplugin.exe';
}

function Local:Test-IsCompiled {
    Get-Variable -Name 'CompiledScript' -ValueOnly -ErrorAction SilentlyContinue
}
#endregion

function Invoke-Setup {
    $RootWarningPreference = $PSCmdlet.GetVariableValue('WarningPreference');
    $RootInformationPreference = $PSCmdlet.GetVariableValue('InformationPreference');
    $RootVerbosePreference = $PSCmdlet.GetVariableValue('VerbosePreference');
    $RootDebugPreference = $PSCmdlet.GetVariableValue('DebugPreference');

    if ($null -ne $RootWarningPreference) {
        $Global:PSDefaultParameterValues['*:WarningAction'] = $RootWarningPreference;
    }

    if ($null -ne $RootInformationPreference) {
        $Global:PSDefaultParameterValues['*:InformationAction'] = $RootInformationPreference;
    }

    $Global:PSDefaultParameterValues['*:Verbose'] = $RootVerbosePreference -match '^(Continue|Break|Suspend|Stop)$';
    $Global:PSDefaultParameterValues['*:Debug'] = $RootDebugPreference -match '^(Continue|Break|Suspend|Stop)$';

    # Module verbose chatter only when actively debugging.
    $Global:PSDefaultParameterValues['*-Module:Verbose'] = $Global:PSDefaultParameterValues['*:Debug'];
}

function Invoke-Teardown {
    foreach ($key in '*:ErrorAction', '*:WarningAction', '*:InformationAction', '*:Verbose', '*:Debug', '*-Module:Verbose') {
        if ($Global:PSDefaultParameterValues.ContainsKey($key)) {
            $null = $Global:PSDefaultParameterValues.Remove($key);
        }
    }
}

<#
.DESCRIPTION
    Wrapper function to invoke a script block with the context of a cmdlet.

    This also handles the output and errors of the script block,
    ensuring they are treated as if they were executed in the context of the cmdlet.

.PARAMETER Cmdlet
    The PSCmdlet object that is invoking the script block.

.PARAMETER ScriptBlock
    The script block to be invoked in the context of the cmdlet.
#>
function Invoke-BlockWrapper {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Cmdlet]$Cmdlet,

        [Parameter(Mandatory)]
        [ScriptBlock]$ScriptBlock
    )

    process {
        $Result = $Cmdlet.InvokeCommand.InvokeScript(
            $Cmdlet.SessionState,
            $ScriptBlock,
            [System.Management.Automation.Runspaces.PipelineResultTypes]::All,
            $Cmdlet.MyInvocation.BoundParameters
        );

        if ($Cmdlet.InvokeCommand.HasErrors) {
            Invoke-Verbose 'Throwing error from wrapped script block!';
            foreach ($err in $Cmdlet.InvokeCommand.Streams.Error) {
                Invoke-Verbose "Viewing error record from wrapped script block: $($err.ToString())";
                Write-Error -ErrorRecord $err;
            }

            $lastError = $Cmdlet.InvokeCommand.Streams.Error[-1];
            $PSCmdlet.ThrowTerminatingError($lastError);
        }


        if ($Result.Count -gt 0) {
            Invoke-Verbose 'Writing output from main function.';
            $Result | ForEach-Object { Write-Output $_; }
        }
    }
}

function Local:Remove-FinishedModule {
    [CmdletBinding()]
    param(
        [Switch]$Teardown
    )

    if ($Teardown) {
        Invoke-Handlers;
        Invoke-Teardown;
    }

    if ($Script:ScriptRestarting) {
        Invoke-Verbose -UnicodePrefix '🔄' -Message 'Restarting script.';
        $Script:ScriptRestarting = $False;
        $Script:ScriptRestarted = $True; # Bread trail for the script to know it's been restarted.
        Invoke-RunMain @PSBoundParameters;
    } else {
        if (-not (Get-Variable -Name 'CompiledScript' -ValueOnly -ErrorAction SilentlyContinue)) {
            Get-Module | ForEach-Object {
                if ($Script:ModuleSnapshot -notcontains $_.Path) {
                    Write-Debug "Removing module $_.";
                    $_ | Remove-Module -Force -Confirm:$False;
                }
            }
        }
    }
}

<#
.SYNOPSIS
    Runs the main function of a script while ensuring that all common modules have been imported.

.DESCRIPTION
    This function is intended to be used as the entry point for all scripts.
    It will ensure that all common modules have been imported, and then invoke the main function of the script.
    This function will automatically clone the repo if required, otherwise try and find the repo on the local machine.

.PARAMETER Cmdlet
    The PSCmdlet object that is invoking the script.
    This is used to determine if the script is being run directly or imported, as well as enrich the environment with the calling context.

.PARAMETER Main
    The main function of the script, which will be invoked only if the script is being run directly.
    If the script is being imported, this function will not be invoked.

.PARAMETER ImportAction
    An optional script block that will be invoked if the script is being imported.
    This is useful for scripts that need to perform some action when imported, but not when run directly.
#>
function Invoke-RunMain {
    [CmdletBinding()]
    Param(
        # If this ends up being null then the script is being imported.
        [Parameter(Mandatory)]
        [AllowNull()]
        [System.Management.Automation.PSCmdlet]$Cmdlet,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [ScriptBlock]$Main,

        [Parameter()]
        [ScriptBlock]$ImportAction,

        [Parameter(DontShow)]
        [Switch]$NotStrict,

        [Parameter(DontShow)]
        [Switch]$HideDisclaimer = ($DontImport -or (Test-IsNableRunner) -or $null),

        $Callstack = (Get-PSCallStack),

        [Parameter(DontShow)]
        $CallingModule = (Get-PSCallStack)[0].InvocationInfo.MyCommand.ScriptBlock.Module
    )

    begin {
        # If the script is being restarted, we have already done this.
        if (-not $Script:ScriptRestarted) {
            if (-not $NotStrict) {
                Set-StrictMode -Version 3;
            }

            if (-not $HideDisclaimer) {
                Invoke-Info -UnicodePrefix '⚠️' -Message 'Disclaimer: This script is provided as is, without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and non-infringement. In no event shall the author or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the script or the use or other dealings in the script.';
            }

            Invoke-Setup;
        }
    }

    process {
        try {
            if ($null -ne $Cmdlet) {
                Invoke-Verbose -UnicodePrefix '🚀' -Message 'Running main function.';
                $Parameters = $Cmdlet.MyInvocation.BoundParameters;
                & $Main @Parameters;

                # Invoke-BlockWrapper -Cmdlet $Cmdlet -ScriptBlock $Main;
                Invoke-Info 'Main function finished successfully.';
            } else {
                Invoke-Verbose -UnicodePrefix '📦' -Message 'Script is being imported, skipping main function.';

                if ($ImportAction) {
                    Invoke-Verbose -UnicodePrefix '📦' -Message 'Running import action.';
                    Invoke-BlockWrapper -Cmdlet:$PSCmdlet -ScriptBlock $ImportAction;
                    Invoke-Info 'Import action finished successfully.';
                }
            }
        } catch [System.Management.Automation.ParseException] {
            Invoke-Error 'Unable to execute script due to a parse error.';
            Invoke-FailedExit -ExitCode 9998 -ErrorRecord $_ -DontExit;
        } catch [System.Management.Automation.RuntimeException] {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $CatchingError = $_;
            } elseif ($null -ne $_.Exception.InnerException -and $_.Exception.InnerException -is [System.Management.Automation.RuntimeException]) {
                $CatchingError = $_.Exception.InnerException.ErrorRecord;
            } else {
                $CatchingError = $_.Exception.ErrorRecord;
            }

            switch ($CatchingError.FullyQualifiedErrorId) {
                'QuickExit' {
                    Invoke-Verbose -UnicodePrefix '✅' -Message 'Main function finished successfully.';
                }
                'FailedExit' {
                    [Int]$Local:ExitCode = $CatchingError.TargetObject;
                    Invoke-Verbose -Message "Script exited with an error code of $Local:ExitCode.";
                    $LASTEXITCODE = $Local:ExitCode;
                }
                'RestartScript' {
                    $Script:ScriptRestarting = $True;
                }
                default {
                    Invoke-Error 'Uncaught Exception during script execution';
                    if (Test-IsCompiled) {
                        $Error.Add($CatchingError);
                        Write-Error -ErrorRecord $CatchingError -ErrorAction Continue -RecommendedAction 'Silent';
                    }
                    Invoke-FailedExit -ExitCode 9999 -ErrorRecord $CatchingError -DontExit;
                }
            }
        } finally {
            if ($null -eq $Cmdlet) {
                Invoke-Verbose "Queueing teardown for when module $CallingModule is removed.";
                Add-ModuleCallback -Module $CallingModule -ScriptBlock {
                    Remove-FinishedModule;
                }
            } else {
                Remove-FinishedModule -Teardown;
            }
        }
    }
}

Export-ModuleMember -Function Invoke-RunMain, Test-IsNableRunner -Variable ScriptRestarted, ScriptRestarting;
