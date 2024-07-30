# Documentation: https://github.com/PowerShell/PSScriptAnalyzer/blob/master/docs/Cmdlets/Invoke-ScriptAnalyzer.md#-settings
# Check rule options via their source in https://github.com/PowerShell/PSScriptAnalyzer/tree/master/Rules
@{
    IncludeDefaultRules = $True;

    Severity            = @(
        'Error'
        'Warning'
    );

    ExcludeRules        = @('PSReviewUnusedParameter');

    Rules               = @{
        PSPlaceOpenBrace  = @{
            Enable             = $True;
            OnSameLine         = $True;
            NewLineAfter       = $True;
            IgnoreOneLineBlock = $True;
        };

        PSPlaceCloseBrace = @{
            Enable = $False;
        };
    };
}

