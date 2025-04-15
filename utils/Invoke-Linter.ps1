Using module ../src/common/Environment.psm1

Invoke-RunMain $PSCmdlet {
    Invoke-EnsureModule -Modules 'PSScriptAnalyzer';

    $Local:Results = Invoke-ScriptAnalyzer `
        -Path $PSSCriptRoot/../src `
        -Recurse `
        -Settings ..\PSScriptAnalyzerSettings.psd1;

    if ($Local:Results.Count -gt 0) {
        $Local:Results | Format-Table -AutoSize;
        throw 'PSScriptAnalyzer found issues';
    }
};
