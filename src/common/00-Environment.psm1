[System.Collections.Generic.List[String]]$Script:ImportedModules = [System.Collections.Generic.List[String]]::new();
[HashTable]$Global:Logging = @{
    Loaded      = $false;
    Error       = $True;
    Warning     = $True;
    Information = $True;
    Verbose     = $VerbosePreference -ne 'SilentlyContinue';
    Debug       = $DebugPreference -ne 'SilentlyContinue';
};

function Invoke-WithLogging {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [String]$Message,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [ScriptBlock]$HasLoggingFunc,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [ScriptBlock]$MissingLoggingFunc
    )

    process {
        if ($Global:Logging.Loaded) {
            $HasLoggingFunc.InvokeReturnAsIs(@($Message));
        } else {
            $MissingLoggingFunc.InvokeReturnAsIs(@($Message));
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
        -Message $Message `
        -HasLoggingFunc { param($Message) if ($UnicodePrefix) { Invoke-Info $Message $UnicodePrefix; } else { Invoke-Info $Message; } } `
        -MissingLoggingFunc { param($Message) Write-Host -ForegroundColor Cyan -Object $Message; };
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
        -Message $Message `
        -HasLoggingFunc { param($Message) if ($UnicodePrefix) { Invoke-Verbose $Message $UnicodePrefix; } else { Invoke-Verbose $Message; } } `
        -MissingLoggingFunc { param($Message) Write-Verbose -Message $Message; };
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
        -Message $Message `
        -HasLoggingFunc { param($Message) if ($UnicodePrefix) { Invoke-Debug $Message $UnicodePrefix } else { Invoke-Debug $Message; }; } `
        -MissingLoggingFunc { param($Message) Write-Debug -Message $Message; };
}

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
        Invoke-EnvDebug -Message "Importing module $Name.";

        if ($Value -is [ScriptBlock]) {
            Invoke-EnvDebug -Message "Module $Name is a script block.";

            if (Get-Module -Name $Name) {
                Remove-Module -Name $Name -Force -Verbose:$False;
            }

            New-Module -ScriptBlock $Value -Name $Name -Verbose:$False | Import-Module -Global -Force -Verbose:$False;
        } else {
            Invoke-EnvDebug -Message "Module $Name is a file or installed module.";

            Import-Module -Name $Value -Global -Force -Verbose:$False;
        }
    }

    # Collect a List of the modules to import.
    if ($Global:CompiledScript) {
        Invoke-EnvVerbose 'Script has been embeded with required modules.';
        [HashTable]$Local:ToImport = $Global:EmbededModules;
    } elseif (Test-Path -Path "$($MyInvocation.MyCommand.Module.Path | Split-Path -Parent)/../../.git") {
        Invoke-EnvVerbose -Message 'Script is in git repository; Using local files.';
        [HashTable]$Local:ToImport = Get-FilsAsHashTable -Path "$($MyInvocation.MyCommand.Module.Path | Split-Path -Parent)/*.psm1";
    } else {
        [String]$Local:RepoPath = "$($env:TEMP)/AMTScripts";

        if (-not (Test-Path -Path $Local:RepoPath)) {
            Invoke-EnvVerbose -UnicodePrefix '♻️' -Message 'Cloning repository.';
            git clone https://github.com/AMTSupport/scripts.git $Local:RepoPath;
        } else {
            Invoke-EnvVerbose -UnicodePrefix '♻️' -Message 'Updating repository.';
            git -C $Local:RepoPath pull;
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
        Invoke-EnvDebug -Message "Removing module $_.";

        if ($_ -eq '01-Logging') {
            $Global:Logging.Loaded = $false;
        }

        Remove-Module -Name $_ -Force -Verbose:$False;
    };

    if ($Global:CompiledScript) {
        Remove-Variable -Scope Global -Name CompiledScript, EmbededModules, Logging;
    }
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
        [Switch]$DontImport,

        [Parameter(DontShow)]
        [Switch]$HideDisclaimer = (([Console]::Title | Split-Path -Leaf) -eq 'fmplugin.exe')
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
            foreach ($Local:Param in @('Verbose','Debug')) {
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
        }

        process {
            try {
                # TODO :: Fix this, it's not working as expected
                # If the script is being run directly, invoke the main function
                # If ($Invocation.CommandOrigin -eq 'Runspace') {
                Invoke-EnvVerbose -UnicodePrefix '🚀' -Message 'Running main function.';
                & $Main;
            } catch {
                if ($_.FullyQualifiedErrorId -eq 'QuickExit') {
                    Invoke-EnvVerbose -UnicodePrefix '✅' -Message 'Main function finished successfully.';
                } elseif ($_.FullyQualifiedErrorId -eq 'FailedExit') {
                    [Int16]$Local:ExitCode = $_.TargetObject;
                    Invoke-EnvVerbose -Message "Script exited with an error code of $Local:ExitCode.";
                    $LASTEXITCODE = $Local:ExitCode;
                } else {
                    Invoke-Error 'Uncaught Exception during script execution';
                    Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_ -DontExit;
                }
            } finally {
                Invoke-Handlers;

                if (-not $Local:DontImport) {
                    Remove-CommonModules;
                }

                # Remove-Variable -Scope Global -Name Logging;
                # [Console]::InputEncoding, [Console]::OutputEncoding = $Local:PreviousEncoding;
            }
        }
    }

    [Boolean]$Local:Verbose = Get-OrFalse $Invocation.BoundParameters 'Verbose';
    [Boolean]$Local:Debug = Get-OrFalse $Invocation.BoundParameters 'Debug';

    Invoke-Inner -Invocation $Invocation -Main $Main -DontImport:$DontImport -HideDisclaimer:$HideDisclaimer -Verbose:$Local:Verbose -Debug:$Local:Debug;
}

Export-ModuleMember -Function Invoke-RunMain, Import-CommonModules, Remove-CommonModules;