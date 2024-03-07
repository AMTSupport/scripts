BeforeDiscovery {
    $Script:ModuleName = & $PSScriptRoot/Base.ps1;
}

AfterAll {
    Remove-CommonModules;
}


Describe '01-Scope.psm1 Tests' {
    Context 'Formatting Tests' {
        It 'Should format a single scope correctly' {
            Mock -Verifiable -ModuleName:$ModuleName -CommandName Get-StackTop -MockWith { return @{MyCommand = @{Name = 'It' } }; };

            Get-ScopeNameFormatted -IsExit:$False | Should -Be 'It';
            Should -Invoke -CommandName Get-StackTop -ModuleName:$ModuleName -Times 1;
        }

        It 'Should format multiple scopes correctly' {
            Mock -Verifiable -ModuleName:$ModuleName -CommandName Get-StackTop -MockWith { return @{MyCommand = @{Name = 'It' } }; };
            Mock -Verifiable -ModuleName:$ModuleName -CommandName Get-Stack -MockWith { return [System.Collections.Stack]::new(@(
                @{MyCommand = @{Name = 'Describe' } },
                @{MyCommand = @{Name = 'Context' } },
                @{MyCommand = @{Name = 'It' } }
            ));};

            Get-ScopeNameFormatted -IsExit:$False | Should -Be 'Describe > Context > It';
            Should -Invoke -CommandName Get-StackTop -ModuleName:$ModuleName -Times 1;
            Should -Invoke -CommandName Get-Stack -ModuleName:$ModuleName -Times 1;
        }

        It 'Should format multiple scopes correctly with exit' {
            Mock -Verifiable -ModuleName:$ModuleName -CommandName Get-StackTop -MockWith { return @{MyCommand = @{Name = 'It' } }; };
            Mock -Verifiable -ModuleName:$ModuleName -CommandName Get-Stack -MockWith { return [System.Collections.Stack]::new(@(
                @{MyCommand = @{Name = 'Describe' } },
                @{MyCommand = @{Name = 'Context' } },
                @{MyCommand = @{Name = 'It' } }
            ));};

            Get-ScopeNameFormatted -IsExit:$True | Should -Be 'Describe > Context < It';
            Should -Invoke -CommandName Get-StackTop -ModuleName:$ModuleName -Times 1;
            Should -Invoke -CommandName Get-Stack -ModuleName:$ModuleName -Times 1;
        }
    }

    Context 'Enter-Scope Tests' {

    }

    Context 'Exit-Scope Tests' {

    }

    Context "Depth Tests" {

    }
}
