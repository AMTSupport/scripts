BeforeDiscovery {
    $Script:ModuleName = & $PSScriptRoot/Base.ps1;
}

AfterAll {
    Remove-CommonModules;
}

Describe 'Utils Tests' {
    Context 'AST Helper functions' {
        Context 'Validate AST Tests' {
            It 'Should return true if the AST has a single correct return type' {
                [ScriptBlock]$Local:Block = {
                    return "Hello, World!";
                };

                Test-ReturnType -InputObject:$Local:Block -ValidTypes 'String' | Should -Be $true;
            }

            It 'Should return true if the AST has has multiple correct return types' {
                [ScriptBlock]$Local:Block = {
                    if ($true) {
                        return "Hello, World!";
                    } else {
                        return "Goodbye, World!";
                    }
                };

                Test-ReturnType -InputObject:$Local:Block -ValidTypes 'String' | Should -Be $true;
            }

            It 'Should return true if the AST has a return statement with $null and AllowNull is $true' {
                [ScriptBlock]$Local:Block = {
                    return $null;
                };

                Test-ReturnType -InputObject:$Local:Block -ValidTypes 'String' -AllowNull | Should -Be $true;
            }
        }

        Context 'Invalid AST Tests' {
            It 'Should return false if the AST has a single incorrect return type' {
                [ScriptBlock]$Local:Block = {
                    return 1;
                };

                Test-ReturnType -InputObject:$Local:Block -ValidTypes 'String' | Should -Be $false;
            }

            It 'Should return false if the AST has has multiple incorrect return types' {
                [ScriptBlock]$Local:Block = {
                    if ($true) {
                        return 1;
                    } else {
                        return 2;
                    }
                };

                Test-ReturnType -InputObject:$Local:Block -ValidTypes 'String' | Should -Be $false;
            }

            It 'Should return false if the AST has no return statement' {
                [ScriptBlock]$Local:Block = {
                    $null;
                };

                Test-ReturnType -InputObject:$Local:Block -ValidTypes 'String' | Should -Be $false;
            }

            It 'Should return false if the AST has a return statement with no value' {
                [ScriptBlock]$Local:Block = {
                    return;
                };

                Test-ReturnType -InputObject:$Local:Block -ValidTypes 'String' | Should -Be $false;
            }

            It 'Should return false if the AST has a return statement with no value even if allowing nulls' {
                [ScriptBlock]$Local:Block = {
                    return;
                };

                Test-ReturnType -InputObject:$Local:Block -ValidTypes 'String' -AllowNull | Should -Be $false;
            }

            It 'Should return false if there is one return statement with a correct type and one with an incorrect type' {
                [ScriptBlock]$Local:Block = {
                    if ($true) {
                        return "Hello, World!";
                    } else {
                        return 1;
                    }
                };

                Test-ReturnType -InputObject:$Local:Block -ValidTypes 'String' | Should -Be $false;
                Test-ReturnType -InputObject:$Local:Block -ValidTypes 'Int32' | Should -Be $false;
            }
        }
    }
}
