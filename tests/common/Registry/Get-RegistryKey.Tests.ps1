Describe "Get-RegistryKey Tests" -Skip:(-not $IsWindows) {
    BeforeAll {
        # Import required modules
        Import-Module "$PSScriptRoot/../../../src/common/Registry.psm1" -Force
        
        # Mock Test-RegistryKey and Get-ItemProperty for testing
        Mock Test-RegistryKey { $true }
        Mock Get-ItemProperty { 
            [PSCustomObject]@{
                TestKey = 'TestValue'
                AnotherKey = 'AnotherValue'
                PSPath = 'TestRegistry::HKLM\Software\Test'
            }
        }
    }

    Context "Basic Functionality" {
        It "Should return registry key value when key exists" {
            Mock Test-RegistryKey { $true }
            Mock Get-ItemProperty { [PSCustomObject]@{ TestKey = 'ExpectedValue' } }
            
            $Result = Get-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            
            $Result | Should -Be 'ExpectedValue'
            Assert-MockCalled Test-RegistryKey -Exactly 1 -Scope It
            Assert-MockCalled Get-ItemProperty -Exactly 1 -Scope It
        }

        It "Should return null when key does not exist" {
            Mock Test-RegistryKey { $false }
            
            $Result = Get-RegistryKey -Path 'HKLM:\Software\Test' -Key 'NonExistentKey'
            
            $Result | Should -Be $null
            Assert-MockCalled Test-RegistryKey -Exactly 1 -Scope It
            Assert-MockCalled Get-ItemProperty -Exactly 0 -Scope It
        }

        It "Should return null when registry path does not exist" {
            Mock Test-RegistryKey { $false }
            
            $Result = Get-RegistryKey -Path 'HKLM:\Software\NonExistent' -Key 'TestKey'
            
            $Result | Should -Be $null
            Assert-MockCalled Test-RegistryKey -Exactly 1 -Scope It
            Assert-MockCalled Get-ItemProperty -Exactly 0 -Scope It
        }
    }

    Context "Data Type Handling" {
        It "Should return string values correctly" {
            Mock Test-RegistryKey { $true }
            Mock Get-ItemProperty { [PSCustomObject]@{ TestKey = 'StringValue' } }
            
            $Result = Get-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            
            $Result | Should -Be 'StringValue'
            $Result | Should -BeOfType [String]
        }

        It "Should return integer values correctly" {
            Mock Test-RegistryKey { $true }
            Mock Get-ItemProperty { [PSCustomObject]@{ TestKey = 42 } }
            
            $Result = Get-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            
            $Result | Should -Be 42
            $Result | Should -BeOfType [Int32]
        }

        It "Should return boolean values correctly" {
            Mock Test-RegistryKey { $true }
            Mock Get-ItemProperty { [PSCustomObject]@{ TestKey = $true } }
            
            $Result = Get-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            
            $Result | Should -Be $true
            $Result | Should -BeOfType [Boolean]
        }

        It "Should return array values correctly" {
            Mock Test-RegistryKey { $true }
            Mock Get-ItemProperty { [PSCustomObject]@{ TestKey = @('Value1', 'Value2', 'Value3') } }
            
            $Result = Get-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            
            $Result | Should -Be @('Value1', 'Value2', 'Value3')
            $Result | Should -BeOfType [Array]
        }

        It "Should handle empty string values" {
            Mock Test-RegistryKey { $true }
            Mock Get-ItemProperty { [PSCustomObject]@{ TestKey = '' } }
            
            $Result = Get-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            
            $Result | Should -Be ''
            $Result | Should -BeOfType [String]
        }

        It "Should handle null values" {
            Mock Test-RegistryKey { $true }
            Mock Get-ItemProperty { [PSCustomObject]@{ TestKey = $null } }
            
            $Result = Get-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            
            $Result | Should -Be $null
        }

        It "Should handle zero values" {
            Mock Test-RegistryKey { $true }
            Mock Get-ItemProperty { [PSCustomObject]@{ TestKey = 0 } }
            
            $Result = Get-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            
            $Result | Should -Be 0
            $Result | Should -BeOfType [Int32]
        }
    }

    Context "Parameter Validation" {
        It "Should require Path parameter" {
            { Get-RegistryKey -Key 'TestKey' } | Should -Throw
        }

        It "Should require Key parameter" {
            { Get-RegistryKey -Path 'HKLM:\Software\Test' } | Should -Throw
        }

        It "Should handle various registry path formats" {
            Mock Test-RegistryKey { $true }
            Mock Get-ItemProperty { [PSCustomObject]@{ TestKey = 'TestValue' } }
            
            Get-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' | Should -Be 'TestValue'
            Get-RegistryKey -Path 'HKCU:\Software\Test' -Key 'TestKey' | Should -Be 'TestValue'
            Get-RegistryKey -Path 'HKEY_LOCAL_MACHINE\Software\Test' -Key 'TestKey' | Should -Be 'TestValue'
        }
    }

    Context "Error Handling" {
        It "Should handle Get-ItemProperty exceptions gracefully" {
            Mock Test-RegistryKey { $true }
            Mock Get-ItemProperty { throw "Access denied" }
            
            { Get-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' } | Should -Throw "Access denied"
        }

        It "Should handle Test-RegistryKey exceptions gracefully" {
            Mock Test-RegistryKey { throw "Registry access error" }
            
            { Get-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' } | Should -Throw "Registry access error"
        }
    }

    Context "Property Extraction" {
        It "Should extract the correct property from Get-ItemProperty result" {
            Mock Test-RegistryKey { $true }
            Mock Get-ItemProperty { 
                [PSCustomObject]@{ 
                    TestKey = 'CorrectValue'
                    OtherKey = 'OtherValue'
                    PSPath = 'SomeRegistryPath'
                    PSChildName = 'SomeChildName'
                } 
            }
            
            $Result = Get-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            
            $Result | Should -Be 'CorrectValue'
            $Result | Should -Not -Be 'OtherValue'
        }

        It "Should handle properties with complex names" {
            Mock Test-RegistryKey { $true }
            Mock Get-ItemProperty { [PSCustomObject]@{ 'Complex-Property_Name.123' = 'ComplexValue' } }
            
            $Result = Get-RegistryKey -Path 'HKLM:\Software\Test' -Key 'Complex-Property_Name.123'
            
            $Result | Should -Be 'ComplexValue'
        }
    }

    Context "Select-Object Usage" {
        It "Should properly use Select-Object -ExpandProperty" {
            Mock Test-RegistryKey { $true }
            Mock Get-ItemProperty { 
                $obj = [PSCustomObject]@{ TestKey = 'TestValue' }
                $obj | Add-Member -MemberType ScriptMethod -Name ToString -Value { return 'MockedObject' } -Force
                return $obj
            }
            
            $Result = Get-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            
            # Should return the actual property value, not the object
            $Result | Should -Be 'TestValue'
            $Result | Should -Not -Be 'MockedObject'
        }
    }
}