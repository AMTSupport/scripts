BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/Exit.psm1" }
AfterAll { Remove-Module Exit -ErrorAction SilentlyContinue }
BeforeAll { $ModuleName = 'Exit' }

Describe 'Invoke-Handlers Tests' {
    It 'Should call Invoke-Handlers with IsFailure $false if ExitCode is 0' {
        Mock -Verifiable -ModuleName:$ModuleName -CommandName Invoke-Handlers -MockWith { } -ParameterFilter { $IsFailure -eq $False; };

        try { Invoke-QuickExit } catch { };

        Should -InvokeVerifiable;
        Should -Invoke -CommandName Invoke-Handlers -ModuleName:$ModuleName -Times 1;
    }

    It 'Should call Invoke-Handlers with IsFailure $true if ExitCode is not 0' {
        Mock -Verifiable -ModuleName:$ModuleName -CommandName Invoke-Handlers -MockWith { } -ParameterFilter { $IsFailure -eq $True; };

        Invoke-FailedExit -ExitCode 1000 -DontExit;

        Should -InvokeVerifiable;
    }

    It 'Should never call Invoke-Handlers more than once' {
        Mock -Verifiable -ModuleName:$ModuleName -CommandName Invoke-Handlers -MockWith { };

        try { Invoke-QuickExit } catch { };
        try { Invoke-QuickExit } catch { };

        Should -Invoke -CommandName Invoke-Handlers -ModuleName:$ModuleName -Times 1;
    }
}
