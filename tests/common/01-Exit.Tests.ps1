BeforeDiscovery {
    Import-Module $PSScriptRoot/../../src/common/00-Environment.psm1;
    Import-CommonModules;
}

AfterAll {
    Remove-CommonModules;
}

Describe '01-Exit.psm1 Tests' {
    Context 'Invoke-Exit' {
        It 'Should throw with a FailedExit ErrorRecord with the ExitCode as the TargetObject' {
            $Local:ThrownError;
            try {
                Invoke-FailedExit -ExitCode 1;
            } catch {
                $Local:ThrownError = $_;
            }

            $Local:ThrownError | Should -Not -BeNullOrEmpty;
            $Local:ThrownError.TargetObject | Should -BeExactly 1;
        }

        It 'Should not throw if DontExit is $true' {
            Invoke-FailedExit -ExitCode 1 -DontExit;
        }

        It 'Should call Invoke-Handlers with IsFailure $true if ExitCode is not 0' {
            Mock -Verifiable -ModuleName '01-Exit' -CommandName Invoke-Handlers -MockWith { } -ParameterFilter { $IsFailure -eq $True; };

            Invoke-FailedExit -ExitCode 1 -DontExit;

            Should -InvokeVerifiable;
        }

        It 'Should call Invoke-Handlers with IsFailure $false if ExitCode is 0' {
            Mock -Verifiable -ModuleName '01-Exit' -CommandName Invoke-Handlers -MockWith { } -ParameterFilter { $IsFailure -eq $False; };

            try { Invoke-QuickExit } catch { };

            Should -InvokeVerifiable;
        }
    }
}
