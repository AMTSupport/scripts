BeforeDiscovery {
    . $PSScriptRoot/../../../src/common/Exit.psm1;
}

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

    It 'Should emit a warning if the ExitCode is not a registered error code' {
        Mock -ModuleName:$ModuleName -Verifiable -CommandName Invoke-Warn -MockWith { } -ParameterFilter { $Message -eq 'No exit description found for code ''1050''' };

        try { Invoke-FailedExit -ExitCode 1050 } catch { };

        Should -ModuleName:$ModuleName -Invoke -CommandName:'Invoke-Warn' -Times 1;
    }

    It 'Should not emit an error if the ExitCode is registered' {

        Mock -ModuleName:$ModuleName -CommandName Invoke-FailedExit -MockWith { } -ParameterFilter { $ExitCode -eq $ExitCode; };

        try { Invoke-FailedExit -ExitCode $ExitCode } catch { };

        Should -Not -Invoke -CommandName Invoke-Warn;
    }
}
