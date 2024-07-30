Using namespace Pester;

[PesterConfiguration]$Config = [PesterConfiguration]@{
    Run          = @{
        Container = $True;
        Path      = '.';
    };
    CodeCoverage = @{
        Enabled               = $True;
        RecursePaths          = $True;
        CoveragePercentTarget = 80;
        Path                  = "$PSScriptRoot/../src/common";
        OutputPath            = "$PSScriptRoot/../artifacts/coverage";
    };
    Should       = @{
        ErrorAction = 'Continue';
    };
}

Invoke-Pester -Configuration $Config
