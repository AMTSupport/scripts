[System.Boolean]$Global:ScriptRestarted = $False;
[System.Boolean]$Global:ScriptRestarting = $False;
[System.Collections.Generic.List[String]]$Script:ImportedModules = [System.Collections.Generic.List[String]]::new();
[HashTable]$Global:Logging = @{
    Loaded      = $false;
    Error       = $True;
    Warning     = $True;
    Information = $True;
    Verbose     = $VerbosePreference -ne 'SilentlyContinue';
    Debug       = $DebugPreference -ne 'SilentlyContinue';
};

#region - Logging Functions

function Invoke-WithLogging {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [ScriptBlock]$HasLoggingFunc,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [ScriptBlock]$MissingLoggingFunc
    )

    process {
        if ($Global:Logging.Loaded) {
            $HasLoggingFunc.InvokeReturnAsIs();
        }
        else {
            $MissingLoggingFunc.InvokeReturnAsIs();
        }
    }
}

function Invoke-EnvInfo {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [String]$Message,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$UnicodePrefix
    )

    Invoke-WithLogging `
        -HasLoggingFunc { if ($UnicodePrefix) { Invoke-Info $Message $UnicodePrefix; } else { Invoke-Info -Message:$Message; } } `
        -MissingLoggingFunc { Write-Host -ForegroundColor Cyan -Object $Message; };
}

function Invoke-EnvVerbose {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [String]$Message,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$UnicodePrefix
    )

    Invoke-WithLogging `
        -HasLoggingFunc { if ($UnicodePrefix) { Invoke-Verbose $Message $UnicodePrefix; } else { Invoke-Verbose -Message:$Message; } } `
        -MissingLoggingFunc { Write-Verbose -Message $Message; };
}

function Invoke-EnvDebug {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [String]$Message,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$UnicodePrefix
    )

    Invoke-WithLogging `
        -HasLoggingFunc { if ($UnicodePrefix) { Invoke-Debug $Message $UnicodePrefix } else { Invoke-Debug -Message:$Message; }; } `
        -MissingLoggingFunc { Write-Debug -Message $Message; };
}
#endregion

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
        }
        else {
            return $false;
        }
    }
}

function Test-OrGetBooleanVariable {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [String]$Name
    )

    process {
        if (Test-Path Variable:Global:$Name) {
            return Get-Variable -Scope Global -Name $Name -ValueOnly;
        }
        else {
            return $false;
        }
    }
}

function Test-IsCompiledScript {
    Test-OrGetBooleanVariable -Name 'CompiledScript';
}

function Test-IsRestartingScript {
    Test-OrGetBooleanVariable -Name 'ScriptRestarting';
}

function Test-IsRestartedScript {
    Test-OrGetBooleanVariable -Name 'ScriptRestarted';
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
#endregion

function Invoke-Setup {
    $PSDefaultParameterValues['*:ErrorAction'] = 'Stop';
    $PSDefaultParameterValues['*:WarningAction'] = 'Continue';
    $PSDefaultParameterValues['*:InformationAction'] = 'Continue';
    $PSDefaultParameterValues['*:Verbose'] = $Global:Logging.Verbose;
    $PSDefaultParameterValues['*:Debug'] = $Global:Logging.Debug;

    $Global:ErrorActionPreference = 'Stop';
}

function Invoke-Teardown {
    $PSDefaultParameterValues.Remove('*:ErrorAction');
    $PSDefaultParameterValues.Remove('*:WarningAction');
    $PSDefaultParameterValues.Remove('*:InformationAction');
    $PSDefaultParameterValues.Remove('*:Verbose');
    $PSDefaultParameterValues.Remove('*:Debug');
}

function Import-CommonModules {
    [HashTable]$Local:ToImport = [Ordered]@{};

    function Get-FilsAsHashTable([String]$Path) {
        [HashTable]$Local:HashTable = [Ordered]@{};

        Get-ChildItem -File -Path "$($MyInvocation.MyCommand.Module.Path | Split-Path -Parent)/*.psm1" | ForEach-Object {
            [System.IO.FileInfo]$Local:File = $_;
            $Local:HashTable[$Local:File.BaseName] = $Local:File.FullName;
        };

        return $Local:HashTable;
    }

    function Import-ModuleOrScriptBlock([String]$Name, [Object]$Value) {
        begin {
            $Local:Hasher = [System.Security.Cryptography.SHA256]::Create();
        }

        process {
            Invoke-EnvDebug -Message "Importing module $Name.";

            if ($Value -is [ScriptBlock]) {
                Invoke-EnvDebug -Message "Module $Name is a script block.";

                $Local:ContentHash = ($Local:Hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes(($Value -as [ScriptBlock]).Ast.Extent.Text)) | ForEach-Object { $_.ToString('x2') }) -join '';
                $Local:ModuleName = "$Name-$Local:ContentHash.psm1";
                $Local:ModulePath = ($env:TEMP | Join-Path -ChildPath "$Local:ModuleName");

                if (-not (Test-Path $Private:ModulePath)) {
                    Set-Content -Path $Private:ModulePath -Value $Value.ToString();
                }

                Import-Module -Name $Private:ModulePath -Global -Force -Verbose:$False -Debug:$False;
            }
            else {
                Invoke-EnvDebug -Message "Module $Name is a file or installed module.";

                Import-Module -Name $Value -Global -Force -Verbose:$False -Debug:$False;
            }
        }
    }

    # Collect a List of the modules to import.
    if (Test-IsCompiledScript) {
        Invoke-EnvVerbose 'Script has been embeded with required modules.';
        [HashTable]$Local:ToImport = $Global:EmbededModules;
    }
    elseif (Test-Path -Path "$($MyInvocation.MyCommand.Module.Path | Split-Path -Parent)/../../.git") {
        Invoke-EnvVerbose 'Script is in git repository; Using local files.';
        [HashTable]$Local:ToImport = Get-FilsAsHashTable -Path "$($MyInvocation.MyCommand.Module.Path | Split-Path -Parent)/*.psm1";
    }
    else {
        [String]$Local:RepoPath = "$($env:TEMP)/AMTScripts";

        if (Get-Command -Name 'git' -ErrorAction SilentlyContinue) {
            if (-not (Test-Path -Path $Local:RepoPath)) {
                Invoke-EnvVerbose -UnicodePrefix '♻️' -Message 'Cloning repository.';
                git clone https://github.com/AMTSupport/scripts.git $Local:RepoPath;
            }
            else {
                Invoke-EnvVerbose -UnicodePrefix '♻️' -Message 'Updating repository.';
                git -C $Local:RepoPath pull;
            }
        }
        else {
            Invoke-EnvInfo -Message 'Git is not installed, unable to update the repository or clone if required.';
        }

        [HashTable]$Local:ToImport = Get-FilsAsHashTable -Path "$Local:RepoPath/src/common/*.psm1";

    }

    # Import PSStyle Before anything else.
    Import-ModuleOrScriptBlock -Name:'00-PSStyle' -Value:$Local:ToImport['00-PSStyle'];

    # Import the modules.
    Invoke-EnvVerbose -Message "Importing $($Local:ToImport.Count) modules.";
    Invoke-EnvVerbose -Message "Modules to import: `n$(($Local:ToImport.Keys | Sort-Object) -join "`n")";
    foreach ($Local:ModuleName in $Local:ToImport.Keys | Sort-Object) {
        $Local:ModuleName = $Local:ModuleName;
        $Local:ModuleValue = $Local:ToImport[$Local:ModuleName];

        if ($Local:ModuleName -eq '00-Environment') {
            continue;
        }

        if ($Local:ModuleName -eq '00-PSStyle') {
            continue;
        }

        Import-ModuleOrScriptBlock -Name $Local:ModuleName -Value $Local:ModuleValue;
        if ($Local:ModuleName -eq '01-Logging') {
            $Global:Logging.Loaded = $true;
        }
    }

    $Script:ImportedModules += $Local:ToImport.Keys;
}

function Remove-CommonModules {
    Invoke-EnvVerbose -Message "Cleaning up $($Script:ImportedModules.Count) imported modules.";
    Invoke-EnvVerbose -Message "Removing modules: `n$(($Script:ImportedModules | Sort-Object -Descending) -join "`n")";
    $Script:ImportedModules | Sort-Object -Descending | ForEach-Object {
        $Private:Module = $_;
        Invoke-EnvDebug -Message "Removing module $Private:Module.";

        # if (Test-IsCompiledScript -and ($Private:Module -eq '00-Environment')) {
        #     Invoke-EnvDebug -Message 'Skipping removal of the environment module.';
        #     return;
        # }

        if ($Local:Module -eq '01-Logging') {
            Invoke-EnvDebug -Message 'Resetting logging state.';
            $Global:Logging.Loaded = $false;
        }

        try {
            Invoke-EnvDebug -Message "Running Remove-Module -Name $Private:Module";
            Remove-Module -Name "$Private:Module*" -Force -Verbose:$False -Debug:$False;

            # The environment module doesn't get a file created for it.
            if (($Private:Module -ne '00-Environment') -and (Test-IsCompiledScript)) {
                Remove-Item -Path ($env:TEMP | Join-Path -ChildPath "$($Private:Module)*");
            }
        }
        catch {
            Invoke-EnvDebug -Message "Failed to remove module $Local:Module";
        }
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
        [System.Management.Automation.InvocationInfo]$Invocation,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [ScriptBlock]$Main,

        [Parameter(DontShow)]
        [Switch]$DontImport = (-not (Test-ExplicitlyCalled -Invocation:$Invocation)),

        [Parameter(DontShow)]
        [Switch]$HideDisclaimer = ($DontImport -or ($Host.UI.RawUI.WindowTitle | Split-Path -Leaf) -eq 'fmplugin.exe')
    )

    # Workaround for embedding modules in a script, can't use Invoke if a scriptblock contains begin/process/clean blocks
    function Invoke-Inner {
        Param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.InvocationInfo]$Invocation,

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
            if (-not $Global:ScriptRestarted) {
                foreach ($Local:Param in @('Verbose', 'Debug')) {
                    if ($Invocation.BoundParameters.ContainsKey($Local:Param)) {
                        $Global:Logging[$Local:Param] = $Invocation.BoundParameters[$Local:Param];
                    }
                }

                if (-not $HideDisclaimer) {
                    Invoke-EnvInfo -UnicodePrefix '⚠️' -Message 'Disclaimer: This script is provided as is, without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and non-infringement. In no event shall the author or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the script or the use or other dealings in the script.';
                }

                if ($Local:DontImport) {
                    Invoke-EnvVerbose -UnicodePrefix '♻️' -Message 'Skipping module import.';
                    return;
                }

                Import-CommonModules;
                Invoke-Setup;
            }
        }

        process {
            try {
                # FIXME :: it's not working as expected, currently not executing if ran from within a script.
                if (Test-ExplicitlyCalled -Invocation:$Invocation) {
                    Invoke-EnvVerbose -UnicodePrefix '🚀' -Message 'Running main function.';

                    $Local:RunBoundParameters = $Invocation.BoundParameters;
                    & $Main @Local:RunBoundParameters;
                }
            }
            catch {
                $Local:CatchingError = $_;
                switch ($Local:CatchingError.FullyQualifiedErrorId) {
                    'QuickExit' {
                        Invoke-EnvVerbose -UnicodePrefix '✅' -Message 'Main function finished successfully.';
                    }
                    # TODO - Remove the error from the record.
                    'FailedExit' {
                        [Int]$Local:ExitCode = $Local:CatchingError.TargetObject;
                        Invoke-EnvVerbose -Message "Script exited with an error code of $Local:ExitCode.";
                        $LASTEXITCODE = $Local:ExitCode;

                        $Global:Error.Remove($Local:CatchingError);
                    }
                    'RestartScript' {
                        $Global:ScriptRestarting = $True;
                    }
                    default {
                        Invoke-Error 'Uncaught Exception during script execution';
                        Invoke-FailedExit -ExitCode 9999 -ErrorRecord $Local:CatchingError -DontExit;
                    }
                }
            }
            finally {
                [Boolean]$Private:WasCompiled = Test-IsCompiledScript;
                [Boolean]$Private:WasRestarted = Test-IsRestartedScript;
                [Boolean]$Private:IsRestarting = Test-IsRestartingScript;

                if (-not $Local:DontImport) {
                    Invoke-Handlers;
                    Invoke-Teardown;

                    # There is no point in removing the modules if the script is restarting.
                    if (-not (Test-IsRestartingScript)) {
                        Remove-CommonModules;

                        if ($Private:WasCompiled) {
                            Remove-Variable -Scope Global -Name CompiledScript, EmbededModules;
                        }

                        Remove-Variable -Scope Global -Name Logging;

                        # Without this explicit check theres a silent error.
                        # It has no effect but it annoys me.
                        if ($Private:WasRestarted) {
                            Remove-Variable -Scope Global -Name ScriptRestarted;
                        }
                    }
                }

                if ($Private:IsRestarting) {
                    Invoke-EnvVerbose -UnicodePrefix '🔄' -Message 'Restarting script.';
                    Remove-Variable -Scope Global -Name ScriptRestarting;
                    Set-Variable -Scope Global -Name ScriptRestarted -Value $True; # Bread trail for the script to know it's been restarted.
                    Invoke-Inner @PSBoundParameters;
                }
            }
        }
    }

    Set-StrictMode -Version 3;
    Invoke-Inner `
        -Invocation $Invocation `
        -Main $Main `
        -DontImport:$DontImport `
        -HideDisclaimer:($HideDisclaimer -or $False) `
        -Verbose:(Get-OrFalse $Invocation.BoundParameters 'Verbose') `
        -Debug:(Get-OrFalse $Invocation.BoundParameters 'Debug');
}

Export-ModuleMember -Function Invoke-RunMain, Import-CommonModules, Remove-CommonModules;
