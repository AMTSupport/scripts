#Documentation: https://github.com/PowerShell/PSScriptAnalyzer/blob/master/docs/Cmdlets/Invoke-ScriptAnalyzer.md#-settings
@{
    # CustomRulePath='path\to\CustomRuleModule.psm1'
    # RecurseCustomRulePath='path\of\customrules'
    IncludeDefaultRules=${true}
    Severity = @(
       'Error'
       'Warning'
    )
    ExcludeRules = @(
       'PSReviewUnusedParameter'
    )
}
