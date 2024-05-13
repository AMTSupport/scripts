BeforeDiscovery {
    $Script:ModuleName = & $PSScriptRoot/Base.ps1;
}

Describe 'Exit Tests' {
    Context 'Invoke-FailedExit' {
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

    Context 'Invoke-QuickExit' {

    }

    Context 'Handlers' {
        It 'Should call Invoke-Handlers with IsFailure $false if ExitCode is 0' {
            Mock -Verifiable -ModuleName:$ModuleName -CommandName Invoke-Handlers -MockWith { } -ParameterFilter { $IsFailure -eq $False; };

            try { Invoke-QuickExit } catch { };

            Should -InvokeVerifiable;
            Should -Invoke -CommandName Invoke-Handlers -ModuleName:$ModuleName -Times 1;
        }

        It 'Should call Invoke-Handlers with IsFailure $true if ExitCode is not 0' {
            Mock -Verifiable -ModuleName:$ModuleName -CommandName Invoke-Handlers -MockWith { } -ParameterFilter { $IsFailure -eq $True; };

            Invoke-FailedExit -ExitCode $Code -DontExit;

            Should -InvokeVerifiable;
            Should -Invoke -CommandName Invoke-Handlers -ModuleName:$ModuleName -Times 1;
        } -ForEach (1..100 | ForEach-Object {
            @{ Code = $_ }
        })
    }

    Context 'Script Tests' {

    }
}
