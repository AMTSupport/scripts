BeforeDiscovery { Import-Module -Name "$PSScriptRoot/../../../src/common/Scope.psm1" }
AfterAll { Remove-Module Scope -ErrorAction SilentlyContinue }

Describe 'Format-ScopeName Tests' {
    It 'Should format a single scope correctly' {
        Mock -Verifiable -ModuleName 'Scope' -CommandName Get-StackTop -MockWith { return @{Invocation = @{MyCommand = @{Name = 'It' } }; }; };

        InModuleScope 'Scope' { Format-ScopeName -IsExit:$False | Should -Be 'It'; }
        Should -Invoke -CommandName Get-StackTop -ModuleName 'Scope' -Times 1;
    }

    It 'Should format multiple scopes correctly' {
        InModuleScope 'Scope' {
            $Script:InvocationStack = [System.Collections.Stack]::new(@(
                @{Invocation = @{MyCommand = @{Name = 'Describe' } }},
                @{Invocation = @{MyCommand = @{Name = 'Context' } }},
                @{Invocation = @{MyCommand = @{Name = 'It' } }}
            ));
        };

        InModuleScope 'Scope' { Format-ScopeName -IsExit:$False | Should -Be 'Describe > Context > It'; }
    }

    It 'Should format multiple scopes correctly with exit' {
        InModuleScope 'Scope' {
            $Script:InvocationStack = [System.Collections.Stack]::new(@(
                @{Invocation = @{MyCommand = @{Name = 'Describe' } }},
                @{Invocation = @{MyCommand = @{Name = 'Context' } }},
                @{Invocation = @{MyCommand = @{Name = 'It' } }}
            ));
        };

        InModuleScope 'Scope' { Format-ScopeName -IsExit:$True | Should -Be 'Describe > Context < It'; }
    }
}
