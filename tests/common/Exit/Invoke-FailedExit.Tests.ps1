BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/Exit.psm1"; }
AfterAll { Remove-Module "Exit"; }

Describe 'Invoke-FailedExit Tests' {
    It 'Should throw with a FailedExit ErrorRecord with the ExitCode as the TargetObject' {
        $Local:ThrownError;
        try {
            Invoke-FailedExit -ExitCode 1;
        }
        catch {
            $Local:ThrownError = $_;
        }

        $Local:ThrownError | Should -Not -BeNullOrEmpty;
        $Local:ThrownError.TargetObject | Should -BeExactly 1;
    }

    It 'Should not throw if DontExit is $true' {
        Invoke-FailedExit -ExitCode 1 -DontExit;
    }
}
