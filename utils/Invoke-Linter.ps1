Import-Module $PSScriptRoot/../src/common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    Invoke-EnsureModules -Modules 'PSScriptAnalyzer';

    $Local:Results = Invoke-ScriptAnalyzer -Path $PSSCriptRoot/../src -Recurse;
    if ($Local:Results.Count -gt 0) {
        $Local:Results | Format-Table -AutoSize;
        throw "PSScriptAnalyzer found issues";
    }
};
