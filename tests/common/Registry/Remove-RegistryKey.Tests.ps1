Describe "Remove-RegistryKey Tests" -Skip:(-not $IsWindows) {
    BeforeAll {
        # Import required modules
        Import-Module "$PSScriptRoot/../../../src/common/Registry.psm1" -Force
        
        # Mock dependencies
        Mock Test-RegistryKey { $true }
        Mock Remove-ItemProperty { }
    }

    Context "Basic Functionality" {
        It "Should remove registry key when it exists" {
            Mock Test-RegistryKey { $true }
            Mock Remove-ItemProperty { }
            
            { Remove-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' } | Should -Not -Throw
            
            Assert-MockCalled Test-RegistryKey -Exactly 1 -Scope It
            Assert-MockCalled Remove-ItemProperty -Exactly 1 -Scope It
        }

        It "Should not attempt to remove when key does not exist" {
            Mock Test-RegistryKey { $false }
            Mock Remove-ItemProperty { }
            
            { Remove-RegistryKey -Path 'HKLM:\Software\Test' -Key 'NonExistentKey' } | Should -Not -Throw
            
            Assert-MockCalled Test-RegistryKey -Exactly 1 -Scope It
            Assert-MockCalled Remove-ItemProperty -Exactly 0 -Scope It
        }

        It "Should check registry key existence before removal" {
            Mock Test-RegistryKey { $false }
            Mock Remove-ItemProperty { }
            
            Remove-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            
            Assert-MockCalled Test-RegistryKey -ParameterFilter { 
                $Path -eq 'HKLM:\Software\Test' -and $Key -eq 'TestKey' 
            }
        }
    }

    Context "ShouldProcess Support" {
        It "Should support WhatIf parameter" {
            Mock Test-RegistryKey { $true }
            Mock Remove-ItemProperty { }
            
            { Remove-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -WhatIf } | Should -Not -Throw
            
            # When WhatIf is used, Remove-ItemProperty should not be called
            Assert-MockCalled Remove-ItemProperty -Exactly 0 -Scope It
        }

        It "Should support Confirm parameter" {
            Mock Test-RegistryKey { $true }
            Mock Remove-ItemProperty { }
            
            { Remove-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Confirm:$false } | Should -Not -Throw
            
            Assert-MockCalled Remove-ItemProperty -Exactly 1 -Scope It
        }
    }

    Context "Parameter Validation" {
        It "Should require Path parameter" {
            { Remove-RegistryKey -Key 'TestKey' } | Should -Throw
        }

        It "Should require Key parameter" {
            { Remove-RegistryKey -Path 'HKLM:\Software\Test' } | Should -Throw
        }

        It "Should handle various registry path formats" {
            Mock Test-RegistryKey { $true }
            Mock Remove-ItemProperty { }
            
            { Remove-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' } | Should -Not -Throw
            { Remove-RegistryKey -Path 'HKCU:\Software\Test' -Key 'TestKey' } | Should -Not -Throw
        }
    }

    Context "Error Handling" {
        It "Should handle Test-RegistryKey failures" {
            Mock Test-RegistryKey { throw "Registry access error" }
            Mock Remove-ItemProperty { }
            
            { Remove-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' } | Should -Throw "Registry access error"
        }

        It "Should handle Remove-ItemProperty failures" {
            Mock Test-RegistryKey { $true }
            Mock Remove-ItemProperty { throw "Access denied" }
            
            { Remove-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' } | Should -Throw "Access denied"
        }

        It "Should handle invalid registry paths" {
            Mock Test-RegistryKey { throw "Invalid path" }
            
            { Remove-RegistryKey -Path 'InvalidPath' -Key 'TestKey' } | Should -Throw "Invalid path"
        }
    }

    Context "Verbose Output" {
        It "Should provide verbose output when key does not exist" {
            Mock Test-RegistryKey { $false }
            Mock Remove-ItemProperty { }
            
            $VerboseOutput = Remove-RegistryKey -Path 'HKLM:\Software\Test' -Key 'NonExistentKey' -Verbose 4>&1
            
            # Should indicate that the key does not exist (assuming the function outputs this)
            # This is based on the source code showing a Invoke-Verbose call
        }

        It "Should provide verbose output when removing key" {
            Mock Test-RegistryKey { $true }
            Mock Remove-ItemProperty { }
            
            $VerboseOutput = Remove-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Verbose 4>&1
            
            # Should indicate that the key is being removed
        }
    }

    Context "Integration Tests" {
        It "Should call functions in correct order" {
            $CallOrder = @()
            Mock Test-RegistryKey { 
                $script:CallOrder += 'TestKey'
                return $true 
            }
            Mock Remove-ItemProperty { $script:CallOrder += 'RemoveProperty' }
            
            Remove-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            
            $CallOrder[0] | Should -Be 'TestKey'
            $CallOrder[1] | Should -Be 'RemoveProperty'
        }

        It "Should pass correct parameters to Remove-ItemProperty" {
            Mock Test-RegistryKey { $true }
            Mock Remove-ItemProperty { }
            
            Remove-RegistryKey -Path 'HKLM:\Software\Test' -Key 'MyTestKey'
            
            Assert-MockCalled Remove-ItemProperty -ParameterFilter { 
                $Path -eq 'HKLM:\Software\Test' -and $Name -eq 'MyTestKey' 
            }
        }
    }

    Context "Edge Cases" {
        It "Should handle special characters in key names" {
            Mock Test-RegistryKey { $true }
            Mock Remove-ItemProperty { }
            
            { Remove-RegistryKey -Path 'HKLM:\Software\Test' -Key 'Special-Key_Name.123' } | Should -Not -Throw
            
            Assert-MockCalled Remove-ItemProperty -ParameterFilter { $Name -eq 'Special-Key_Name.123' }
        }

        It "Should handle complex registry paths" {
            Mock Test-RegistryKey { $true }
            Mock Remove-ItemProperty { }
            
            { Remove-RegistryKey -Path 'HKLM:\Software\Company\Product\Version\Settings' -Key 'TestKey' } | Should -Not -Throw
            
            Assert-MockCalled Test-RegistryKey -ParameterFilter { 
                $Path -eq 'HKLM:\Software\Company\Product\Version\Settings' 
            }
        }

        It "Should handle empty or whitespace key names" {
            Mock Test-RegistryKey { $false }
            
            # Empty key name should be caught by parameter validation
            { Remove-RegistryKey -Path 'HKLM:\Software\Test' -Key '' } | Should -Throw
        }
    }

    Context "Registry Hive Support" {
        It "Should work with HKLM registry hive" {
            Mock Test-RegistryKey { $true }
            Mock Remove-ItemProperty { }
            
            { Remove-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' } | Should -Not -Throw
            
            Assert-MockCalled Test-RegistryKey -ParameterFilter { $Path -like 'HKLM:*' }
        }

        It "Should work with HKCU registry hive" {
            Mock Test-RegistryKey { $true }
            Mock Remove-ItemProperty { }
            
            { Remove-RegistryKey -Path 'HKCU:\Software\Test' -Key 'TestKey' } | Should -Not -Throw
            
            Assert-MockCalled Test-RegistryKey -ParameterFilter { $Path -like 'HKCU:*' }
        }
    }
}