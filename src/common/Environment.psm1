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
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.InvocationInfo]$Invocation,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [ScriptBlock]$Main
    )

    #region - Begin
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
        }
        else {
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

            New-Module -ScriptBlock $Local:ModuleDefinition -AsCustomObject | Import-Module -Name $Local:ModuleKey -Global;
        }
    } else {
        Write-Verbose -Message "✅ Modules to import: `n`t$($Local:ToImport.Name -join "`n`t")";

        Import-Module -Name $Local:ToImport.FullName -Global;
    }

    $Local:ImportedModules += $Local:ToImport;
    #endregion - Begin

    #region - Process
    try {
        # If the script is being run directly, invoke the main function
        if ($Invocation.CommandOrigin -eq 'Runspace') {
            Write-Verbose -Message '✅ Running main function.';

            Invoke-Command -ScriptBlock $Main;
        }
    } catch {
        $Local:DeepestException = $_.Exception;
        while ($true) {
            if (-not $Local:DeepestException.InnerException) {
                break;
            }

            $Local:DeepestException = $Local:DeepestException.InnerException;
        }

        Write-Host -ForegroundColor Red -Object '❌ Uncaught Exception during script execution';
        Write-Host -ForegroundColor Red -Object "❌ Exception: $($Local:DeepestException.Message)";

        $Local:Position = $Local:DeepestException.ErrorRecord.InvocationInfo.PositionMessage;
        if ($Local:Position) {
            Write-Host -ForegroundColor Red -Object "❌ Position: $Local:Position";
        }
    }
    #endregion - Process

    #region - End
    Write-Verbose -Message "♻️ Cleaning up $($Local:ImportedModules.Count) imported modules.";
    if ($Global:CompiledScript) {
        Write-Verbose -Message "✅ Imported modules: `n`t$($Local:ImportedModules.Keys -join "`n`t")";

        $Local:ImportedModules.Keys | ForEach-Object { Remove-Module -Name $_ -Force -ErrorAction SilentlyContinue | Out-Null; };

        $Global:CompiledScript = $null;
        $Global:EmbededModules = $null;
    } else {
        Write-Verbose -Message "✅ Imported modules: `n`t$($Local:ImportedModules -join "`n`t")";

        $Local:ImportedModules | ForEach-Object { Remove-Module -FullyQualifiedName $_.FullName -Force -ErrorAction SilentlyContinue | Out-Null; }
    }
    #endregion - End
}

Export-ModuleMember -Function Invoke-EnsureAdministrator,Invoke-RunMain;
