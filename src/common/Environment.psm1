[System.Collections.Generic.List[String]]$Script:ImportedModules = [System.Collections.Generic.List[String]]::new();

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

function Import-CommonModules([HashTable]$CommonParams) {
    [System.Management.Automation.OrderedHashtable]$Local:ToImport = [Ordered]@{};

    function Get-FilsAsHashTable([String]$Path) {
        [System.Management.Automation.OrderedHashtable]$Local:HashTable = [Ordered]@{};

        Get-ChildItem -File -Path "$($MyInvocation.MyCommand.Module.Path | Split-Path -Parent)/*.psm1" | ForEach-Object {
            [System.IO.FileInfo]$Local:File = $_;
            $Local:HashTable[$Local:File.BaseName] = $Local:File.FullName;
        };

        return $Local:HashTable;
    }

    # Collect a List of the modules to import.
    if ($Global:CompiledScript) {
        Write-Verbose -Message '✅ Script has been embeded with required modules.';
        [System.Management.Automation.OrderedHashtable]$Local:ToImport = $Global:EmbededModules;
    } elseif (Test-Path -Path "$($MyInvocation.MyCommand.Module.Path | Split-Path -Parent)/../../.git") {
        Write-Verbose -Message '✅ Script is in git repository; Using local files.';
        [System.Management.Automation.OrderedHashtable]$Local:ToImport = Get-FilsAsHashTable -Path "$($MyInvocation.MyCommand.Module.Path | Split-Path -Parent)/*.psm1";
    } else {
        [String]$Local:RepoPath = "$($env:TEMP)/AMTScripts";

        if (-not (Test-Path -Path $Local:RepoPath)) {
            Write-Verbose -Message '♻️ Cloning repository.';
            git clone https://github.com/AMTSupport/scripts.git $Local:RepoPath;
        } else {
            Write-Verbose -Message '♻️ Updating repository.';
            git -C $Local:RepoPath pull;
        }

        [System.Management.Automation.OrderedHashtable]$Local:ToImport = Get-FilsAsHashTable -Path "$Local:RepoPath/src/common/*.psm1";
    }

    # Import the modules.
    Write-Verbose -Message "♻️ Importing $($Local:ToImport.Count) modules.";
    Write-Verbose -Message "✅ Modules to import: `n`t$($Local:ToImport.Keys -join "`n`t")";
    foreach ($Local:Module in $Local:ToImport.GetEnumerator()) {
        $Local:ModuleName = $Local:Module.Key;
        $Local:ModuleValue = $Local:Module.Value;

        if ($Local:ModuleName -eq 'Environment') {
            continue;
        }

        $Local:Module = if ($Local:ModuleValue -is [ScriptBlock]) {
            New-Module -ScriptBlock $Local:ModuleValue -Name $Local:ModuleName -ArgumentList $Local:CommonParams | Import-Module -Global -Force;
        } else {
            Import-Module -Name $Local:ModuleValue -ArgumentList $Local:CommonParams -Global -Force;
        }
    }

    $Script:ImportedModules += $Local:ToImport.Keys;
}

function Remove-CommonModules {
    Invoke-Verbose -Prefix '♻️' -Message "Cleaning up $($Script:ImportedModules.Count) imported modules.";
    Invoke-Verbose -Prefix '✅' -Message "Removing modules: `n`t$($Script:ImportedModules -join "`n`t")";
    $Script:ImportedModules | ForEach-Object { Remove-Module -Name $_ -Force; };

    if ($Global:CompiledScript) {
        Remove-Variable -Scope Global -Name CompiledScript, EmbededModules;
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
        [Switch]$HideDisclaimer
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
            # $InformationPreference = 'Continue';
            [HashTable]$Local:CommonParams = @{ InformationPreference = 'Continue'; };
            [String[]]$Local:CopyParams = @('WhatIf','Verbose','Debug','ErrorAction','WarningAction','InformationAction','ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable');
            foreach ($Local:Param in $Invocation.BoundParameters.Keys) {
                Write-Host "Ecountered parameter $Local:Param with value $($Invocation.BoundParameters[$Local:Param])"
                if ($Local:CopyParams -contains $Local:Param) {
                    Write-Host "Copying parameter $Local:Param with value $($Invocation.BoundParameters[$Local:Param])"
                    $Local:CommonParams[$Local:Param] = $Invocation.BoundParameters[$Local:Param];
                }
            }

            # Setup UTF8 encoding to ensure that all output is encoded correctly.
            $Local:PreviousEncoding = [Console]::InputEncoding, [Console]::OutputEncoding;
            $OutputEncoding = [Console]::InputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding;

            if (-not $HideDisclaimer) {
                Write-Host -ForegroundColor Yellow -Object '⚠️ Disclaimer: This script is provided "as is", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and non-infringement. In no event shall the author or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the script or the use or other dealings in the script.';
            }

            if ($Local:DontImport) {
                Write-Verbose -Message '♻️ Skipping module import.';
                return;
            }

            Import-CommonModules;
        }

        process {
            try {
                # TODO :: Fix this, it's not working as expected
                # If the script is being run directly, invoke the main function
                # if ($Invocation.CommandOrigin -eq 'Runspace') {
                Invoke-Verbose -UnicodePrefix '🚀' -Message 'Running main function.';
                & $Main;
            } catch {
                if ($_.FullyQualifiedErrorId -eq 'QuickExit') {
                    Invoke-Verbose -UnicodePrefix '✅' -Message 'Main function finished successfully.';
                } elseif ($_.FullyQualifiedErrorId -eq 'FailedExit') {
                    [Int16]$Local:ExitCode = $_.TargetObject;
                    Invoke-Verbose -Message "Script exited with an error code of $Local:ExitCode.";
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

                [Console]::InputEncoding, [Console]::OutputEncoding = $Local:PreviousEncoding;
            }
        }
    }

    [Boolean]$Local:Verbose = Get-OrFalse $Invocation.BoundParameters 'Verbose';
    [Boolean]$Local:Debug = Get-OrFalse $Invocation.BoundParameters 'Debug';

    Invoke-Inner -Invocation $Invocation -Main $Main -DontImport:$DontImport -HideDisclaimer:$HideDisclaimer -Verbose:$Local:Verbose -Debug:$Local:Debug;
}

Export-ModuleMember -Function Invoke-RunMain, Import-CommonModules, Remove-CommonModules;
