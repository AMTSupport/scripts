BeforeDiscovery {
    $Script:ModuleName = & $PSScriptRoot/Base.ps1;
}

Describe '01-Scope.psm1 Tests' {
    Context 'Formatting Tests' {
        It 'Should format a single scope correctly' {
            Mock -Verifiable -ModuleName:$ModuleName -CommandName Get-StackTop -MockWith { return @{Invocation = @{MyCommand = @{Name = 'It' } }; }; };

            Format-ScopeName -IsExit:$False | Should -Be 'It';
            Should -Invoke -CommandName Get-StackTop -ModuleName:$ModuleName -Times 1;
        }

        It 'Should format multiple scopes correctly' {
            Mock -Verifiable -ModuleName:$ModuleName -CommandName Get-StackTop -MockWith { return @{Invocation = @{MyCommand = @{Name = 'It' } }; }; };
            Mock -Verifiable -ModuleName:$ModuleName -CommandName Get-Stack -MockWith { return [System.Collections.Stack]::new(@(
                @{MyCommand = @{Name = 'Describe' } },
                @{MyCommand = @{Name = 'Context' } },
                @{MyCommand = @{Name = 'It' } }
            ));};

            Format-ScopeName -IsExit:$False | Should -Be 'Describe > Context > It';
            Should -Invoke -CommandName Get-StackTop -ModuleName:$ModuleName -Times 1;
            Should -Invoke -CommandName Get-Stack -ModuleName:$ModuleName -Times 1;
        }

        It 'Should format multiple scopes correctly with exit' {
            Mock -Verifiable -ModuleName:$ModuleName -CommandName Get-StackTop -MockWith { return @{Invocation = @{MyCommand = @{Name = 'It' } }; }; };
            Mock -Verifiable -ModuleName:$ModuleName -CommandName Get-Stack -MockWith { return [System.Collections.Stack]::new(@(
                @{Invocation = @{MyCommand = @{Name = 'Describe' } } },
                @{Invocation = @{MyCommand = @{Name = 'Context' } } },
                @{Invocation = @{MyCommand = @{Name = 'It' } } }
            ));};

            Format-ScopeName -IsExit:$True | Should -Be 'Describe > Context < It';
            Should -Invoke -CommandName Get-StackTop -ModuleName:$ModuleName -Times 1;
            Should -Invoke -CommandName Get-Stack -ModuleName:$ModuleName -Times 1;
        }

        It 'Formatting variabels should work' {
            $Private:Formatted = Format-Variable @{ foo = 'bar'; hello = 'world'; this = @('super', @{ cool = 'list'; }) };
            $Private:Formatted | Should -Be @"
{
  foo = bar
  hello = world
  this = [
    super,
    {
      cool = list
    }
  ]
}
"@;
        }
    }

    Context 'Enter-Scope Tests' {
        It 'Should push a new scope' {
            Mock -Verifiable -ModuleName:$ModuleName -CommandName Get-Stack -MockWith { return [System.Collections.Stack]::new() };
            Mock -Verifiable -ModuleName:$ModuleName -CommandName Get-StackTop -MockWith { return @{Invocation = @{MyCommand = @{Name = 'Describe' }; }; }; };

            function Test-Scope {
                begin { Enter-Scope; }
            }

            Test-Scope;
            Should -Invoke -CommandName Get-Stack -ModuleName:$ModuleName -Times 1;
            Should -Invoke -CommandName Get-StackTop -ModuleName:$ModuleName -Times 1;
            Should -Invoke -CommandName Push-Stack -ModuleName:$ModuleName -Times 1;
        }
    }

    Context 'Exit-Scope Tests' {

    }

    Context "Depth Tests" {

    }
}
