[PesterConfiguration]@{
    Run          = @{
        Path          = 'tests';
        PassThru      = $True;
        TestExtension = '.Tests.ps1';
    }
    Filter       = @{ }
    CodeCoverage = @{
        Enabled = $False
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
