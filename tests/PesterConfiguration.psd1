[PesterConfiguration]@{
    Run          = @{
        Path          = 'tests';
        PassThru      = $True;
        TestExtension = '.Tests.ps1';
    }
    Filter       = @{ }
    CodeCoverage = @{
        Enabled      = $True;
        CoveragePercentTarget = 80;
        OutputFormat = 'JaCoCo';
        OutputPath   = 'tests\Coverage\PesterCodeCoverage.xml';
        Path         = 'src';
        RecursePaths = $True;
    }
    TestResult   = @{
        Enabled      = $True;
        OutputFormat = 'NUnit2.5';
        OutputPath   = 'tests\TestResults\PesterTestResults.xml';
    }
    Output       = @{
        Verbosity           = 'Detailed';
        StackTraceVerbosity = 'Filtered'
    }
}
