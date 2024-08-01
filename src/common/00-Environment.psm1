Using module ./00-Utils.psm1
Using module ./01-Logging.psm1
Using module ./01-Scope.psm1
Using module ./02-Exit.psm1

Using namespace System.Management.Automation.Language;
Using namespace System.Collections.Generic

[System.Boolean]$Script:ScriptRestarted = $False;
[System.Boolean]$Script:ScriptRestarting = $False;
[System.Collections.Generic.List[String]]$Script:ImportedModules = [System.Collections.Generic.List[String]]::new();

#region - Utility Functions
function Get-OrFalse {
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

function Test-ExplicitlyCalled {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.InvocationInfo]$Invocation
    )

    process {
        $Global:Invocation = $Invocation;
        # $Global:PSCallStack = Get-PSCallStack;

        # Being ran from terminal
        # CommandOrigin: Runspace
        # InvocationName: relative path to script name
        if ($Invocation.CommandOrigin -eq 'Runspace' -and ($Invocation.InvocationName | Split-Path -Leaf) -eq $Invocation.MyCommand.Name) {
            return $True;
        }

        # Being imported
        # CommandOrigin: Internal
        #


        # if ($Invocation.MyCommand.CommandType -eq 'Script') {
        #     Write-Host 'The script is being run directly from the terminal.'
        # } elseif ($null -ne $Invocation.MyCommand.Module) {
        #     Write-Host 'The script has been imported using Import-Module.'
        # } elseif ($Invocation.MyCommand.CommandType -eq 'Script' -or $Invocation.MyCommand.CommandType -eq 'ExternalScript') {
        #     Write-Host 'The script is being run from within another script.'
        # } else {
        #     Write-Host 'The script context is unclear.'
        # }
        return $True;
    }
}

function Test-IsNableRunner {
    $WindowName = $Host.UI.RawUI.WindowTitle;
    if (-not $WindowName) { return $False; };
    return ($WindowName | Split-Path -Leaf) -eq 'fmplugin.exe';
}
#endregion

function Invoke-Setup {
    $PSDefaultParameterValues['*:ErrorAction'] = 'Stop';
    $PSDefaultParameterValues['*:WarningAction'] = 'Continue';
    $PSDefaultParameterValues['*:InformationAction'] = 'Continue';
    $PSDefaultParameterValues['*:Verbose'] = $Logging.Verbose;
    $PSDefaultParameterValues['*:Debug'] = $Logging.Debug;

    $Global:ErrorActionPreference = 'Stop';
}

function Invoke-Teardown {
    $PSDefaultParameterValues.Remove('*:ErrorAction');
    $PSDefaultParameterValues.Remove('*:WarningAction');
    $PSDefaultParameterValues.Remove('*:InformationAction');
    $PSDefaultParameterValues.Remove('*:Verbose');
    $PSDefaultParameterValues.Remove('*:Debug');
}

function Remove-Modules {
    # Get the AST of the script and look for all the using module statements.
    # Then remove the modules in reverse order.

    # Get the AST of the script.
    [String]$Private:CallingScript = (Get-PSCallStack)[-1].Location;
    [System.Management.Automation.Language.Ast]$Private:ScriptAst = [Parser]::ParseFile($Private:CallingScript, [ref]$null, [ref]$null);

    # Find all the using module statements.
    [List[UsingStatementAst]]$Private:UsingStatements = [List[UsingStatementAst]]::new();
    $Private:ScriptAst.FindAll({ $args[0] -is [UsingStatementAst] -and ($args[0] -as [UsingStatementAst]).UsingStatementKind -eq 'Module' }, $true) | ForEach-Object {
        $Private:UsingStatements.Add(([UsingStatementAst]$_).Name);
    };

    Invoke-Verbose -Message "Cleaning up $($Private:UsingStatements.Count) imported modules.";
    Invoke-Verbose -Message "Removing modules: `n$(($Private:UsingStatements | Sort-Object -Descending) -join "`n")";
    $Private:UsingStatements | ForEach-Object {
        $Private:ModuleName = $_;
        Invoke-Debug -Message "Removing module $Private:ModuleName.";
        Remove-Module -Name $Private:ModuleName -Force -Verbose:$False -Debug:$False;
    };
}

<#
.SYNOPSIS
    Runs the main function of a script while ensuring that all common modules have been imported.

.DESCRIPTION
    This function is intended to be used as the entry point for all scripts.
    It will ensure that all common modules have been imported, and then invoke the main function of the script.
    This function will automatically clone the repo if required, otherwise try and find the repo on the local machine.

.PARAMETER Invocation
    The InvocationInfo object of the script.

.PARAMETER Main
    The main function of the script, which will be invoked only if the script is being run directly.
    If the script is being imported, this function will not be invoked.
#>
function Invoke-RunMain {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCmdlet]$Cmdlet,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [ScriptBlock]$Main,

        [Parameter(DontShow)]
        [Switch]$NotStrict = $False,

        [Parameter(DontShow)]
        [Switch]$DontImport = (-not (Test-ExplicitlyCalled -Invocation:$Cmdlet.MyInvocation)),

        [Parameter(DontShow)]
        [Switch]$HideDisclaimer = ($DontImport -or (Test-IsNableRunner))
    )

    # Workaround for embedding modules in a script, can't use Invoke if a scriptblock contains begin/process/clean blocks
    function Invoke-Inner {
        Param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.PSCmdlet]$Cmdlet,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [ScriptBlock]$Main,

            [Parameter(DontShow)]
            [Switch]$DontImport,

            [Parameter(DontShow)]
            [Switch]$HideDisclaimer
        )

        begin {
            # If the script is being restarted, we have already done this.
            if (-not $Script:ScriptRestarted) {
                foreach ($Local:Param in @('Verbose', 'Debug')) {
                    if ($Cmdlet.MyInvocation.BoundParameters.ContainsKey($Local:Param)) {
                        $Logging[$Local:Param] = $Cmdlet.MyInvocation.BoundParameters[$Local:Param];
                    }
                }

                if (-not $HideDisclaimer) {
                    Invoke-Info -UnicodePrefix '⚠️' -Message 'Disclaimer: This script is provided as is, without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and non-infringement. In no event shall the author or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the script or the use or other dealings in the script.';
                }

                if ($Local:DontImport) {
                    Invoke-Verbose -UnicodePrefix '♻️' -Message 'Skipping module import.';
                    return;
                }

                Invoke-Setup;
            }
        }

        process {
            try {
                # FIXME :: it's not working as expected, currently not executing if ran from within a script.
                if (Test-ExplicitlyCalled -Invocation:$Cmdlet.MyInvocation) {
                    Invoke-Verbose -UnicodePrefix '🚀' -Message 'Running main function.';

                    $Local:RunBoundParameters = $Cmdlet.MyInvocation.BoundParameters;
                    $Cmdlet.InvokeCommand.InvokeScript(
                        $Cmdlet.SessionState,
                        $Main,
                        [System.Management.Automation.Runspaces.PipelineResultTypes]::All,
                        $Local:RunBoundParameters
                    );
                }
            } catch {
                $Local:CatchingError = $_;
                switch ($Local:CatchingError.FullyQualifiedErrorId) {
                    'QuickExit' {
                        Invoke-Verbose -UnicodePrefix '✅' -Message 'Main function finished successfully.';
                    }
                    # TODO - Remove the error from the record.
                    'FailedExit' {
                        [Int]$Local:ExitCode = $Local:CatchingError.TargetObject;
                        Invoke-Verbose -Message "Script exited with an error code of $Local:ExitCode.";
                        $LASTEXITCODE = $Local:ExitCode;
                        $Error.RemoveAt(0);
                    }
                    'RestartScript' {
                        $Script:ScriptRestarting = $True;
                    }
                    default {
                        Invoke-Error 'Uncaught Exception during script execution';
                        Invoke-FailedExit -ExitCode 9999 -ErrorRecord $Local:CatchingError -DontExit;
                    }
                }
            } finally {
                if (-not $Local:DontImport) {
                    Invoke-Handlers;
                    Invoke-Teardown;

                    # There is no point in removing the modules if the script is restarting.
                    if (-not $Script:ScriptRestarting) {
                        Invoke-Debug 'Cleaning up'
                        Remove-Modules;
                    }
                }

                if ($Script:ScriptRestarting) {
                    Invoke-Verbose -UnicodePrefix '🔄' -Message 'Restarting script.';
                    Remove-Variable -Scope Global -Name ScriptRestarting;
                    $Script:ScriptRestarted = $True; # Bread trail for the script to know it's been restarted.
                    Invoke-Inner @PSBoundParameters;
                }
            }
        }
    }

    if (-not $NotStrict) {
        Set-StrictMode -Version 3;
    }
    Invoke-Inner `
        -Cmdlet $Cmdlet `
        -Main $Main `
        -DontImport:$DontImport `
        -HideDisclaimer:($HideDisclaimer -or $False) `
        -Verbose:(Get-OrFalse $Cmdlet.MyInvocation.BoundParameters 'Verbose') `
        -Debug:(Get-OrFalse $Cmdlet.MyInvocation.BoundParameters 'Debug');
}

Export-ModuleMember -Function Invoke-RunMain, Remove-CommonModules, Test-IsNableRunner -Variable ScriptRestarted, ScriptRestarting;
