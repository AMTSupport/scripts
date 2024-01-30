BeforeDiscovery {
    Import-Module $PSScriptRoot/../../src/common/00-Environment.psm1;
    Import-CommonModules;
}

AfterAll {
    Remove-CommonModules;
}


Describe '00-Scope.psm1 Tests' {
    Context 'Scope Formatting Tests' {
        It 'Should format a single scope correctly' {
            Mock -Verifiable -ModuleName '00-Scope' -CommandName Get-StackTop -MockWith { return @{MyCommand = @{Name = "It"}}; };

            Get-ScopeNameFormatted -IsExit:$False | Should -Be 'It';
            Should -Invoke -CommandName Get-StackTop -ModuleName '00-Scope' -Times 1;
        }

        It 'Should format multiple scopes correctly' {
            Mock -Verifiable -ModuleName '00-Scope' -CommandName Get-StackTop -MockWith { return @{MyCommand = @{Name = "It"}}; };
            Mock -Verifiable -ModuleName '00-Scope' -CommandName Get-Stack -MockWith { return [System.Collections.Stack]::new(@(
                @{MyCommand = @{Name = 'Describe' } },
                @{MyCommand = @{Name = 'Context' } },
                @{MyCommand = @{Name = 'It' } }
            ));};

            Get-ScopeNameFormatted -IsExit:$False | Should -Be 'Describe > Context > It';
            Should -Invoke -CommandName Get-StackTop -ModuleName '00-Scope' -Times 1;
            Should -Invoke -CommandName Get-Stack -ModuleName '00-Scope' -Times 1;
        }
    }

    Context 'Enter-Scope Tests' {

    }

    Context 'Exit-Scope Tests' {

    }

    Context 'Formatting Tests' {

    }

    Context "Depth Tests" {

    }
}
