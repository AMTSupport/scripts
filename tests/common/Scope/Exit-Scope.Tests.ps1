BeforeDiscovery { Import-Module $PSScriptRoot/../../../src/common/Scope.psm1 }
AfterAll { Remove-Module Scope }

Describe 'Exit-Scope Tests' {
    BeforeAll {
        InModuleScope 'Scope' {
            $Script:InvocationStack = [System.Collections.Stack]::new(@(
                @{Invocation = @{MyCommand = @{Name = 'Describe' } }},
                @{Invocation = @{MyCommand = @{Name = 'Context' } }},
                @{Invocation = @{MyCommand = @{Name = 'It' } }}
            ));
        }
    }

    It 'Should pop the latest stack item' {
        InModuleScope 'Scope' {
            $VerbosePreference = 'SilentlyContinue';
            Exit-Scope;
            $Script:InvocationStack.Count | Should -Be 2;
            $Script:InvocationStack.Peek().Invocation.MyCommand.Name | Should -Be 'Context';
        }
    }

    It 'Should handle multiple exit calls' {
        InModuleScope 'Scope' {
            $VerbosePreference = 'SilentlyContinue';
            Exit-Scope;
            Exit-Scope;
            $Script:InvocationStack.Count | Should -Be 1;
            $Script:InvocationStack.Peek().Invocation.MyCommand.Name | Should -Be 'Describe';
        }
    }
}
