#Documentation: https://github.com/PowerShell/PSScriptAnalyzer/blob/master/docs/Cmdlets/Invoke-ScriptAnalyzer.md#-settings
@{
    IncludeDefaultRules = $True;

    Severity            = @(
        'Error'
        'Warning'
    );

    ExcludeRules        = @();

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
