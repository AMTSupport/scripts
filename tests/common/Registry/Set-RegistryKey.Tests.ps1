Describe "Set-RegistryKey Tests" -Skip:(-not $IsWindows) {
    BeforeAll {
        # Import required modules
        Import-Module "$PSScriptRoot/../../../src/common/Registry.psm1" -Force

        # Mock dependencies for cross-platform testing
        Mock Invoke-EnsureRegistryPath { }
        Mock Set-ItemProperty { }
    }

    Context "Basic Functionality" {
        It "Should set registry key with string value" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value 'TestValue' -Kind 'String' } | Should -Not -Throw

            Should -Invoke Invoke-EnsureRegistryPath -Exactly 1 -Scope It
            Should -Invoke Set-ItemProperty -Exactly 1 -Scope It
        }

        It "Should set registry key with DWord value" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value '42' -Kind 'DWord' } | Should -Not -Throw

            Should -Invoke Set-ItemProperty -ParameterFilter { $Type -eq 'DWord' } -Exactly 1 -Scope It
        }

        It "Should set registry key with Binary value" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value 'BinaryData' -Kind 'Binary' } | Should -Not -Throw

            Should -Invoke Set-ItemProperty -ParameterFilter { $Type -eq 'Binary' } -Exactly 1 -Scope It
        }

        It "Should ensure registry path exists before setting value" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            Set-RegistryKey -Path 'HKLM:\Software\TestPath\SubPath' -Key 'TestKey' -Value 'TestValue' -Kind 'String'

            Should -Invoke Invoke-EnsureRegistryPath -ParameterFilter {
                $Root -eq 'HKLM' -and $Path -eq 'Software\TestPath\SubPath'
            } -Exactly 1 -Scope It
        }
    }

    Context "Registry Value Types" {
        It "Should support String registry type" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value 'StringValue' -Kind 'String' } | Should -Not -Throw

            Should -Invoke Set-ItemProperty -ParameterFilter { $Type -eq 'String' }
        }

        It "Should support DWord registry type" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value '123' -Kind 'DWord' } | Should -Not -Throw

            Should -Invoke Set-ItemProperty -ParameterFilter { $Type -eq 'DWord' }
        }

        It "Should support QWord registry type" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value '9223372036854775807' -Kind 'QWord' } | Should -Not -Throw

            Should -Invoke Set-ItemProperty -ParameterFilter { $Type -eq 'QWord' }
        }

        It "Should support Binary registry type" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value 'BinaryData' -Kind 'Binary' } | Should -Not -Throw

            Should -Invoke Set-ItemProperty -ParameterFilter { $Type -eq 'Binary' }
        }

        It "Should support ExpandString registry type" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value '%SystemRoot%\System32' -Kind 'ExpandString' } | Should -Not -Throw

            Should -Invoke Set-ItemProperty -ParameterFilter { $Type -eq 'ExpandString' }
        }

        It "Should support MultiString registry type" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value 'Value1;Value2;Value3' -Kind 'MultiString' } | Should -Not -Throw

            Should -Invoke Set-ItemProperty -ParameterFilter { $Type -eq 'MultiString' }
        }

        It "Should support None registry type" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value '' -Kind 'None' } | Should -Not -Throw

            Should -Invoke Set-ItemProperty -ParameterFilter { $Type -eq 'None' }
        }
    }

    Context "Path Processing" {
        It "Should extract root correctly from HKLM path" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value 'TestValue' -Kind 'String'

            Should -Invoke Invoke-EnsureRegistryPath -ParameterFilter { $Root -eq 'HKLM' }
        }

        It "Should extract root correctly from HKCU path" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            Set-RegistryKey -Path 'HKCU:\Software\Test' -Key 'TestKey' -Value 'TestValue' -Kind 'String'

            Should -Invoke Invoke-EnsureRegistryPath -ParameterFilter { $Root -eq 'HKCU' }
        }

        It "Should extract path correctly by removing root prefix" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            Set-RegistryKey -Path 'HKLM:\Software\Microsoft\Windows' -Key 'TestKey' -Value 'TestValue' -Kind 'String'

            Should -Invoke Invoke-EnsureRegistryPath -ParameterFilter { $Path -eq 'Software\Microsoft\Windows' }
        }

        It "Should handle complex nested paths" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            Set-RegistryKey -Path 'HKLM:\Software\Company\Product\Version\Settings' -Key 'TestKey' -Value 'TestValue' -Kind 'String'

            Should -Invoke Invoke-EnsureRegistryPath -ParameterFilter {
                $Root -eq 'HKLM' -and $Path -eq 'Software\Company\Product\Version\Settings'
            }
        }
    }

    Context "ShouldProcess Support" {
        It "Should support WhatIf parameter" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value 'TestValue' -Kind 'String' -WhatIf } | Should -Not -Throw

            # When WhatIf is used, Set-ItemProperty should not be called
            Should -Invoke Set-ItemProperty -Exactly 0 -Scope It
        }

        It "Should support Confirm parameter" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value 'TestValue' -Kind 'String' -Confirm:$false } | Should -Not -Throw

            Should -Invoke Set-ItemProperty -Exactly 1 -Scope It
        }
    }

    Context "Parameter Validation" {
        It "Should require Path parameter" {
            { Set-RegistryKey -Key 'TestKey' -Value 'TestValue' -Kind 'String' } | Should -Throw
        }

        It "Should require Key parameter" {
            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Value 'TestValue' -Kind 'String' } | Should -Throw
        }

        It "Should require Value parameter" {
            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Kind 'String' } | Should -Throw
        }

        It "Should require Kind parameter" {
            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value 'TestValue' } | Should -Throw
        }

        It "Should validate Kind parameter values" {
            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value 'TestValue' -Kind 'InvalidType' } | Should -Throw
        }
    }

    Context "Error Handling" {
        It "Should handle Invoke-EnsureRegistryPath failures" {
            Mock Invoke-EnsureRegistryPath { throw "Access denied" }
            Mock Set-ItemProperty { }

            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value 'TestValue' -Kind 'String' } | Should -Throw "Access denied"
        }

        It "Should handle Set-ItemProperty failures" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { throw "Registry write error" }

            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value 'TestValue' -Kind 'String' } | Should -Throw "Registry write error"
        }

        It "Should handle invalid registry paths" {
            Mock Invoke-EnsureRegistryPath { throw "Invalid path" }

            { Set-RegistryKey -Path 'InvalidPath' -Key 'TestKey' -Value 'TestValue' -Kind 'String' } | Should -Throw "Invalid path"
        }
    }

    Context "Integration Tests" {
        It "Should call functions in correct order" {
            $CallOrder = @()
            Mock Invoke-EnsureRegistryPath { $script:CallOrder += 'EnsurePath' }
            Mock Set-ItemProperty { $script:CallOrder += 'SetProperty' }

            Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value 'TestValue' -Kind 'String'

            $CallOrder[0] | Should -Be 'EnsurePath'
            $CallOrder[1] | Should -Be 'SetProperty'
        }

        It "Should pass correct parameters to Set-ItemProperty" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'MyKey' -Value 'MyValue' -Kind 'String'

            Should -Invoke Set-ItemProperty -ParameterFilter {
                $Path -eq 'HKLM:\Software\Test' -and
                $Name -eq 'MyKey' -and
                $Value -eq 'MyValue' -and
                $Type -eq 'String'
            }
        }
    }

    Context "Edge Cases" {
        It "Should handle empty string values" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value '' -Kind 'String' } | Should -Not -Throw

            Should -Invoke Set-ItemProperty -ParameterFilter { $Value -eq '' }
        }

        It "Should handle special characters in key names" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'Special-Key_Name.123' -Value 'TestValue' -Kind 'String' } | Should -Not -Throw

            Should -Invoke Set-ItemProperty -ParameterFilter { $Name -eq 'Special-Key_Name.123' }
        }

        It "Should handle special characters in values" {
            Mock Invoke-EnsureRegistryPath { }
            Mock Set-ItemProperty { }

            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value 'Value with spaces and $pecial chars!' -Kind 'String' } | Should -Not -Throw

            Should -Invoke Set-ItemProperty -ParameterFilter { $Value -eq 'Value with spaces and $pecial chars!' }
        }
    }
}
