Describe "Test-RegistryKey Tests" {
    BeforeAll {
        # Import required modules
        Import-Module "$PSScriptRoot/../../../src/common/Registry.psm1" -Force
        
        # Mock dependencies for cross-platform testing
        Mock Test-Path { $true }
        Mock Get-ItemProperty { 
            [PSCustomObject]@{
                TestKey = 'TestValue'
                PSPath = 'TestRegistry::HKLM\Software\Test'
            }
        }
    }

    Context "Basic Functionality" {
        It "Should return True when registry key exists and has property" {
            Mock Test-Path { $true }
            Mock Get-ItemProperty { [PSCustomObject]@{ TestKey = 'TestValue' } }
            
            $Result = Test-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            
            $Result | Should -Be $true
            Assert-MockCalled Test-Path -Exactly 1 -Scope It
            Assert-MockCalled Get-ItemProperty -Exactly 1 -Scope It
        }

        It "Should return False when registry path does not exist" {
            Mock Test-Path { $false }
            
            $Result = Test-RegistryKey -Path 'HKLM:\Software\NonExistent' -Key 'TestKey'
            
            $Result | Should -Be $false
            Assert-MockCalled Test-Path -Exactly 1 -Scope It
            Assert-MockCalled Get-ItemProperty -Exactly 0 -Scope It
        }

        It "Should return False when registry key does not exist" {
            Mock Test-Path { $true }
            Mock Get-ItemProperty { $null }
            
            $Result = Test-RegistryKey -Path 'HKLM:\Software\Test' -Key 'NonExistentKey'
            
            $Result | Should -Be $false
            Assert-MockCalled Test-Path -Exactly 1 -Scope It
            Assert-MockCalled Get-ItemProperty -Exactly 1 -Scope It
        }

        It "Should return False when Get-ItemProperty throws error" {
            Mock Test-Path { $true }
            Mock Get-ItemProperty { throw "Property does not exist" } -ParameterFilter { $ErrorAction -eq 'SilentlyContinue' }
            
            $Result = Test-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            
            $Result | Should -Be $false
            Assert-MockCalled Test-Path -Exactly 1 -Scope It
            Assert-MockCalled Get-ItemProperty -Exactly 1 -Scope It
        }
    }

    Context "Parameter Validation" {
        It "Should require Path parameter" {
            { Test-RegistryKey -Key 'TestKey' } | Should -Throw
        }

        It "Should require Key parameter" {
            { Test-RegistryKey -Path 'HKLM:\Software\Test' } | Should -Throw
        }

        It "Should handle various registry paths" {
            Mock Test-Path { $true }
            Mock Get-ItemProperty { [PSCustomObject]@{ TestKey = 'TestValue' } }
            
            Test-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' | Should -Be $true
            Test-RegistryKey -Path 'HKCU:\Software\Test' -Key 'TestKey' | Should -Be $true
            Test-RegistryKey -Path 'HKEY_LOCAL_MACHINE\Software\Test' -Key 'TestKey' | Should -Be $true
        }
    }

    Context "Error Handling" {
        It "Should handle Test-Path exceptions" {
            Mock Test-Path { throw "Access denied" }
            
            { Test-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' } | Should -Throw "Access denied"
        }

        It "Should handle invalid registry paths" {
            Mock Test-Path { $false }
            
            $Result = Test-RegistryKey -Path 'InvalidPath' -Key 'TestKey'
            
            $Result | Should -Be $false
        }
    }

    Context "Edge Cases" {
        It "Should handle empty string values in registry" {
            Mock Test-Path { $true }
            Mock Get-ItemProperty { [PSCustomObject]@{ TestKey = '' } }
            
            $Result = Test-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            
            $Result | Should -Be $true
        }

        It "Should handle null values in registry" {
            Mock Test-Path { $true }
            Mock Get-ItemProperty { [PSCustomObject]@{ TestKey = $null } }
            
            $Result = Test-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            
            $Result | Should -Be $true
        }

        It "Should handle zero values in registry" {
            Mock Test-Path { $true }
            Mock Get-ItemProperty { [PSCustomObject]@{ TestKey = 0 } }
            
            $Result = Test-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            
            $Result | Should -Be $true
        }

        It "Should handle boolean values in registry" {
            Mock Test-Path { $true }
            Mock Get-ItemProperty { [PSCustomObject]@{ TestKey = $false } }
            
            $Result = Test-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            
            $Result | Should -Be $true
        }
    }

    Context "PathType Validation" {
        It "Should validate path as Container" {
            Mock Test-Path { $true } -ParameterFilter { $PathType -eq 'Container' }
            Mock Get-ItemProperty { [PSCustomObject]@{ TestKey = 'TestValue' } }
            
            $Result = Test-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            
            $Result | Should -Be $true
            Assert-MockCalled Test-Path -ParameterFilter { $PathType -eq 'Container' }
        }
    }
}