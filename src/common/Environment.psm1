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
        [ScriptBlock]$Main
    )

    # Workaround for embedding modules in a script, can't use Invoke if a scriptblock contains begin/process/clean blocks
    function Invoke-Inner {
        Param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Management.Automation.InvocationInfo]$Invocation,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [ScriptBlock]$Main
        )

        begin {
            [HashTable]$Local:CommonParams = @{};
            [String[]]$Local:CopyParams = @('WhatIf','Verbose','Debug','ErrorAction','WarningAction','InformationAction','ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable');
            foreach ($Local:Param in $Invocation.BoundParameters.Keys) {
                if ($Local:CopyParams -contains $Local:Param) {
                    $Local:CommonParams[$Local:Param] = $Invocation.BoundParameters[$Local:Param];
                }
            }

            # Setup UTF8 encoding to ensure that all output is encoded correctly.
            $Local:PreviousEncoding = [Console]::InputEncoding, [Console]::OutputEncoding;
            $OutputEncoding = [Console]::InputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding;

            Write-Host -ForegroundColor Yellow -Object '⚠️ Disclaimer: This script is provided "as is", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and non-infringement. In no event shall the author or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the script or the use or other dealings in the script.';

            $Local:ImportedModules = [System.Collections.Generic.List[String]]::new();
            if ($Global:CompiledScript) {
                Write-Verbose -Message '✅ Script has been embeded with required modules.';
                $Local:ToImport = $Global:EmbededModules;
            } elseif (Test-Path -Path "$($MyInvocation.MyCommand.Module.Path | Split-Path -Parent)/../../.git") {
                Write-Verbose -Message '✅ Script is in git repository; Using local files.';
                $Local:ToImport = Get-ChildItem -Path "$($MyInvocation.MyCommand.Module.Path | Split-Path -Parent)/*.psm1";
            } else {
                $Local:RepoPath = "$($env:TEMP)/AMTScripts";

                if (-not (Test-Path -Path $Local:RepoPath)) {
                    Write-Verbose -Message '♻️ Cloning repository.';
                    git clone https://github.com/AMTSupport/scripts.git $Local:RepoPath;
                } else {
                    Write-Verbose -Message '♻️ Updating repository.';
                    git -C $Local:RepoPath pull;
                }

                Write-Verbose -Message '♻️ Collecting common modules.';
                $Local:ToImport = Get-ChildItem -Path "$Local:RepoPath/src/common/*.psm1";
            }

            Write-Verbose -Message "♻️ Importing $($Local:ToImport.Count) modules.";
            if ($Global:CompiledScript) {
                Write-Verbose -Message "✅ Modules to import: `n`t$($Local:ToImport.Keys -join "`n`t")";

                foreach ($Local:Module in $Local:ToImport.GetEnumerator()) {
                    $Local:ModuleKey = $Local:Module.Key;
                    $Local:ModuleDefinition = $Local:Module.Value;

                    $Local:Module = New-Module -ScriptBlock $Local:ModuleDefinition -Name $Local:ModuleKey | Import-Module -Global -Force -ArgumentList $Local:CommonParams;
                }
            } else {
                Write-Verbose -Message "✅ Modules to import: `n`t$($Local:ToImport.Name -join "`n`t")";
                Import-Module -Name $Local:ToImport.FullName -Global -ArgumentList $Local:CommonParams;
            }

            $Local:ImportedModules += $Local:ToImport;
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

                ([Int16]$Local:ModuleCount, [String[]]$Local:ModuleNames) = if ($Global:CompiledScript) {
                    $Local:ImportedModules.GetEnumerator().Count, $Local:ImportedModules.GetEnumerator().Keys
                } else {
                    $Local:ImportedModules.Count, $Local:ImportedModules
                };

                Invoke-Verbose -Prefix '♻️' -Message "Cleaning up $($Local:ModuleCount) imported modules.";
                Invoke-Verbose -Prefix '✅' -Message "Removing modules: `n`t$($Local:ModuleNames -join "`n`t")";

                if ($Global:CompiledScript) {
                    $Local:ImportedModules.Keys | ForEach-Object {
                        Remove-Module -Name $_ -Force;
                    };

                    $Global:CompiledScript = $null;
                    $Global:EmbededModules = $null;
                } else {
                    $Local:ImportedModules | ForEach-Object {
                        Remove-Module -Name $_.BaseName -Force;
                    }
                }

                [Console]::InputEncoding, [Console]::OutputEncoding = $Local:PreviousEncoding;
            }
        }
    }

    [Boolean]$Local:Verbose = Get-OrFalse $Invocation.BoundParameters 'Verbose';
    [Boolean]$Local:Debug = Get-OrFalse $Invocation.BoundParameters 'Debug';

    Invoke-Inner -Invocation $Invocation -Main $Main -Verbose:$Local:Verbose -Debug:$Local:Debug;
}

Export-ModuleMember -Function Invoke-RunMain;
