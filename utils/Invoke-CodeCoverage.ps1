Using namespace Pester;

[PesterConfiguration]$Config = New-PesterConfiguration;
$Config.Run.Path = ".";
$Config.CodeCoverage.Enabled = $true;
$Config.CodeCoverage.Path = "$PSScriptRoot/../src/common";
$Config.CodeCoverage.CoveragePercentTarget = 80;
$Config.CodeCoverage.OutputPath = "$PSScriptRoot/../artifacts/coverage";
$Config.CodeCoverage.RecursePaths = $true;

Invoke-Pester -Configuration $Config
