function Invoke-EnsureAdministrator {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning -Message '❌ Not running as administrator!  Please re-run your terminal session as Administrator, and try again.'
        throw "Not running as administrator!";
    }

    Write-Verbose -Message '✅ Running as administrator.';
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
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNull()]
        [System.Management.Automation.InvocationInfo]$Invocation,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNull()]
        [ScriptBlock]$Main
    )

    begin {
        $Local:ImportedModules = [System.Collections.Generic.List[String]]::new();
        $Local:ToImport = Get-ChildItem -Path "$($MyInvocation.MyCommand.Module.Path | Split-Path -Parent)/*.psm1";

        Write-Verbose -Message "♻️ Importing $($Local:ToImport.Count) modules.";
        Write-Verbose -Message "✅ Modules to import: `n`t$($Local:ToImport.Name -join "`n`t")";

        Import-Module -Name $Local:ToImport.FullName -Global;
        $Local:ImportedModules += $Local:ToImport;
    }

    end {
        Write-Verbose -Message "♻️ Cleaning up $($Local:ImportedModules.Count) imported modules.";
        Write-Verbose -Message "✅ Imported modules: `n`t$($Local:ImportedModules -join "`n`t")";

        $Local:ImportedModules | ForEach-Object { Remove-Module -FullyQualifiedName $_.FullName -Force -ErrorAction SilentlyContinue | Out-Null; }
    }

    process {
        Trap {
            $Local:DeepestException = $_.Exception;
            while ($true) {
                if (-not $Local:DeepestException.InnerException) {
                    break;
                }

                $Local:DeepestException = $Local:DeepestException.InnerException;
            }

            Write-Host -ForegroundColor Red -Object "❌ Uncaught Exception during script execution";
            Write-Host -ForegroundColor Red -Object "❌ Exception: $($Local:DeepestException.Message)";

            $Local:Position = $Local:DeepestException.ErrorRecord.InvocationInfo.PositionMessage;
            if ($Local:Position) {
                Write-Host -ForegroundColor Red -Object "❌ Position: $Local:Position";
            }
        }

        # If the script is being run directly, invoke the main function
        if ($Invocation.CommandOrigin -eq 'Runspace') {
            Write-Verbose -Message '✅ Running main function.';

            Invoke-Command -ScriptBlock $Main;
        }
    }
}

Export-ModuleMember -Function Invoke-EnsureAdministrator,Invoke-RunMain;
