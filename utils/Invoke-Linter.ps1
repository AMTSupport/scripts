Import-Module $PSScriptRoot/../src/common/Environment.psm1;
Invoke-RunMain $PSCommandPath {
    Invoke-EnsureModule -Modules 'PSScriptAnalyzer';

    $Local:Results = Invoke-ScriptAnalyzer `
        -Path $PSSCriptRoot/../src `
        -Recurse `
        -ExcludeRule PSReviewUnusedParameter;

    if ($Local:Results.Count -gt 0) {
        $Local:Results | Format-Table -AutoSize;
        throw 'PSScriptAnalyzer found issues';
    }
};
