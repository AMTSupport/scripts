BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/Exit.psm1"; }

Describe 'Invoke-FailedExit Tests' {
    It 'Should throw with the ExitCode as the TargetObject' {
        $ThrownError;
        try {
            Invoke-FailedExit -ExitCode 1;
        }
        catch {
            $ThrownError = $_;
        }

        $ThrownError.TargetObject | Should -BeExactly 1;
    }

    It 'Should not throw if DontExit is $true' {
        { Invoke-FailedExit -ExitCode 1 -DontExit; } | Should -Not -Throw;
    }
}
