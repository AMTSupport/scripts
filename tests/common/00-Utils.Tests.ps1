BeforeDiscovery {
    $Script:ModuleName = & $PSScriptRoot/Base.ps1;
}

Describe 'Utils Tests' {
    Context 'AST Helper functions' {
        Context 'Validate AST Tests' {
            It 'True if AST has a single return <Value> of <Type>' {
                [ScriptBlock]$Local:Block = [ScriptBlock]::Create("return $Value;");

                Get-ReturnType -InputObject:$Local:Block | Should -Be $Type;
                Test-ReturnType -InputObject:$Local:Block -ValidTypes $Type | Should -Be $True;
            } -TestCases @(
                @{ Type = [String]; Value = '"Hello, World!"'; }
                @{ Type = [Int32]; Value = '1'; }
                @{ Type = [Int64]; Value = '1L';}
                @{ Type = [Double]; Value = '1.0'; }
                @{ Type = [Decimal]; Value = '1.0d'; }
                @{ Type = [Boolean]; Value = '$true'; }
                @{ Type = [PSCustomObject]; Value = '[PSCustomObject]@{}'; }
                @{ Type = [Hashtable]; Value = '@{}'; }
                @{ Type = [System.Object[]]; Value = '@()'; }
                @{ Type = [ScriptBlock]; Value = '{ }'; }
            )

            It 'True if AST has multiple returns (<Value1> <Value2>) of <Type>' {
                [ScriptBlock]$Local:Block = [ScriptBlock]::Create("return $Value1; return $Value2;");

                Get-ReturnType -InputObject:$Local:Block | Should -Be $Type;
                Test-ReturnType -InputObject:$Local:Block -ValidTypes $Type | Should -Be $true;
            } -TestCases @(
                @{ Type = [String]; Value1 = '"Hello, World!"'; Value2 = '"Goodbye, World!"'; }
                @{ Type = [Int32]; Value1 = '1'; Value2 = '2'; }
                @{ Type = [Int64]; Value1 = '1L'; Value2 = '2L'; }
                @{ Type = [Double]; Value1 = '1.0'; Value2 = '2.0'; }
                @{ Type = [Decimal]; Value1 = '1.0d'; Value2 = '2.0d'; }
                @{ Type = [Boolean]; Value1 = '$true'; Value2 = '$false'; }
                @{ Type = [PSCustomObject]; Value1 = '[PSCustomObject]@{}'; Value2 = '[PSCustomObject]@{}'; }
                @{ Type = [Hashtable]; Value1 = '@{}'; Value2 = '@{}'; }
                @{ Type = [System.Object[]]; Value1 = '@()'; Value2 = '@()'; }
                @{ Type = [ScriptBlock]; Value1 = '{ }'; Value2 = '{ }'; }
            )

            It 'True if AST has multiple returns (<Value1> <Value2>) of types <Type1> <Type2>' {
                [ScriptBlock]$Local:Block = [ScriptBlock]::Create("return $Value1; return $Value2;");

                $Local:ReturnTypes = Get-ReturnType -InputObject:$Local:Block;
                $Local:ReturnTypes | Should -Contain $Type1;
                $Local:ReturnTypes | Should -Contain $Type2;

                Test-ReturnType -InputObject:$Local:Block -ValidTypes @($Type1, $Type2) | Should -Be $true;
            } -TestCases @(
                @{ Type1 = [String]; Type2 = [Int32]; Value1 = '"Hello, World!"'; Value2 = '1'; }
                @{ Type1 = [Int32]; Type2 = [Int64]; Value1 = '1'; Value2 = '1L'; }
                @{ Type1 = [Int64]; Type2 = [Double]; Value1 = '1L'; Value2 = '1.0'; }
                @{ Type1 = [Double]; Type2 = [Decimal]; Value1 = '1.0'; Value2 = '1.0d'; }
                @{ Type1 = [Decimal]; Type2 = [Boolean]; Value1 = '1.0d'; Value2 = '$true'; }
                @{ Type1 = [Boolean]; Type2 = [PSCustomObject]; Value1 = '$true'; Value2 = '[PSCustomObject]@{}'; }
                @{ Type1 = [PSCustomObject]; Type2 = [Hashtable]; Value1 = '[PSCustomObject]@{}'; Value2 = '@{}'; }
                @{ Type1 = [Hashtable]; Type2 = [System.Object[]]; Value1 = '@{}'; Value2 = '@()'; }
                @{ Type1 = [System.Object[]]; Type2 = [ScriptBlock]; Value1 = '@()'; Value2 = '{ }'; }
            )

            It 'Should return true if the AST has a return statement with $null and AllowNull is $true' {
                [ScriptBlock]$Local:Block = {
                    return $null;
                };

                Test-ReturnType -InputObject:$Local:Block -ValidTypes @([String]) -AllowNull | Should -Be $true;
            }
        }

        Context 'Invalid AST Tests' {
            It 'Should return false if the AST has a single incorrect return type' {
                [ScriptBlock]$Local:Block = {
                    return 1;
                };

                Test-ReturnType -InputObject:$Local:Block -ValidTypes @([String]) | Should -Be $false;
            }

            It 'Should return false if the AST has has multiple incorrect return types' {
                [ScriptBlock]$Local:Block = {
                    if ($true) {
                        return 1;
                    } else {
                        return 2;
                    }
                };

                Test-ReturnType -InputObject:$Local:Block -ValidTypes @([String]) | Should -Be $false;
            }

            It 'Should return false if the AST has no return statement' {
                [ScriptBlock]$Local:Block = {
                    $null;
                };

                Test-ReturnType -InputObject:$Local:Block -ValidTypes @([String]) | Should -Be $false;
            }

            It 'Should return false if the AST has a return statement with no value' {
                [ScriptBlock]$Local:Block = {
                    return;
                };

                Test-ReturnType -InputObject:$Local:Block -ValidTypes @([String]) | Should -Be $false;
            }

            It 'Should return false if the AST has a return statement with no value even if allowing nulls' {
                [ScriptBlock]$Local:Block = {
                    return;
                };

                Test-ReturnType -InputObject:$Local:Block -ValidTypes @([String]) -AllowNull | Should -Be $false;
            }

            It 'Should return false if there is one return statement with a correct type and one with an incorrect type' {
                [ScriptBlock]$Local:Block = {
                    if ($true) {
                        return "Hello, World!";
                    } else {
                        return 1;
                    }
                };

                Test-ReturnType -InputObject:$Local:Block -ValidTypes @([String]) | Should -Be $false;
                Test-ReturnType -InputObject:$Local:Block -ValidTypes @([Int32]) | Should -Be $false;
            }
        }
    }
}
