BeforeDiscovery { Import-Module $PSScriptRoot/../../../src/common/Scope.psm1 }
AfterAll { Remove-Module Scope -ErrorAction SilentlyContinue }
BeforeAll { $ModuleName = 'Scope' }

Describe 'Enter-Scope Tests' {
    BeforeEach {
        InModuleScope $ModuleName {
            $Script:InvocationStack = [System.Collections.Stack]::new();
        }
    }

    It 'Should push a new scope' {
        function Test-Scope {
            begin { Enter-Scope; }
        }

        Test-Scope;
        InModuleScope $ModuleName {
            (Get-Stack).Count | Should -Be 1;
            (Get-StackTop).Invocation.MyCommand.Name | Should -Be 'Test-Scope';
        }
    }

    It 'Should push a new scope to the top of the stack' {
        function Test-ScopeOne { begin { Enter-Scope; } }
        function Test-ScopeTwo { begin { Enter-Scope; } }

        Test-ScopeOne;
        Test-ScopeTwo;
        InModuleScope $ModuleName {
            (Get-Stack).Count | Should -Be 2;
            (Get-StackTop).Invocation.MyCommand.Name | Should -Be 'Test-ScopeTwo';
        }
    }
}
