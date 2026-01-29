Using module ../src/common/Environment.psm1
using module PSScriptAnalyzer

Invoke-RunMain $PSCmdlet {
    $Local:Results = Invoke-ScriptAnalyzer `
        -Path $PSSCriptRoot/../src `
        -Recurse `
        -Settings ..\PSScriptAnalyzerSettings.psd1;

    if ($Local:Results.Count -gt 0) {
        $Local:Results | Format-Table -AutoSize;
        throw 'PSScriptAnalyzer found issues';
    }
};
