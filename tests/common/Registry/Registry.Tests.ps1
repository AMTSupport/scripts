Describe "Registry Module Tests" -Skip:(-not $IsWindows) {
    BeforeAll {
        # Import required modules with force to ensure clean state
        Import-Module "$PSScriptRoot/../../../src/common/Registry.psm1" -Force
    }

    Context "Module Import" {
        It "Should import Registry module successfully" {
            Get-Module -Name Registry* | Should -Not -BeNullOrEmpty
        }

        It "Should export expected functions" {
            $ExportedFunctions = (Get-Module -Name Registry*).ExportedFunctions.Keys
            $ExportedFunctions | Should -Contain 'Invoke-EnsureRegistryPath'
            $ExportedFunctions | Should -Contain 'Test-RegistryKey'
            $ExportedFunctions | Should -Contain 'Get-RegistryKey'
            $ExportedFunctions | Should -Contain 'Set-RegistryKey'
            $ExportedFunctions | Should -Contain 'Remove-RegistryKey'
            $ExportedFunctions | Should -Contain 'Invoke-OnEachUserHive'
        }
    }

    Context "Test-RegistryKey Basic Tests" {
        BeforeEach {
            # Mock dependencies for cross-platform testing
            Mock Test-Path { $true } -ModuleName Registry
            Mock Get-ItemProperty {
                [PSCustomObject]@{ TestKey = 'TestValue' }
            } -ModuleName Registry
        }

        It "Should return True when registry key exists" -Skip:($IsLinux -or $IsMacOS) {
            # Skip on non-Windows platforms as this requires actual registry access
            Mock Test-Path { $true } -ModuleName Registry
            Mock Get-ItemProperty { [PSCustomObject]@{ TestKey = 'TestValue' } } -ModuleName Registry

            $Result = Test-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            $Result | Should -Be $true
        }

        It "Should return False when registry path does not exist" -Skip:($IsLinux -or $IsMacOS) {
            Mock Test-Path { $false } -ModuleName Registry

            $Result = Test-RegistryKey -Path 'HKLM:\Software\NonExistent' -Key 'TestKey'
            $Result | Should -Be $false
        }

        It "Should accept mandatory parameters" {
            { Test-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' } | Should -Not -Throw
        }
    }

    Context "Get-RegistryKey Basic Tests" {
        It "Should require Path and Key parameters" {
            { Get-RegistryKey } | Should -Throw
        }

        It "Should accept valid parameters without throwing" {
            Mock Test-RegistryKey { $false } -ModuleName Registry

            { Get-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' } | Should -Not -Throw
        }

        It "Should return null when Test-RegistryKey returns false" {
            Mock Test-RegistryKey { $false } -ModuleName Registry

            $Result = Get-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey'
            $Result | Should -Be $null
        }
    }

    Context "Set-RegistryKey Basic Tests" {
        It "Should require all mandatory parameters" {
            { Set-RegistryKey } | Should -Throw
            { Set-RegistryKey -Path 'HKLM:\Software\Test' } | Should -Throw
            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' } | Should -Throw
            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value 'TestValue' } | Should -Throw
        }

        It "Should accept all required parameters" {
            Mock Invoke-EnsureRegistryPath { } -ModuleName Registry
            Mock Set-ItemProperty { } -ModuleName Registry

            { Set-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' -Value 'TestValue' -Kind 'String' } | Should -Not -Throw
        }
    }

    Context "Remove-RegistryKey Basic Tests" {
        It "Should require Path and Key parameters" {
            { Remove-RegistryKey } | Should -Throw
            { Remove-RegistryKey -Path 'HKLM:\Software\Test' } | Should -Throw
        }

        It "Should accept required parameters" {
            Mock Test-RegistryKey { $false } -ModuleName Registry

            { Remove-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' } | Should -Not -Throw
        }
    }

    Context "Invoke-EnsureRegistryPath Basic Tests" {
        It "Should require Root and Path parameters" {
            { Invoke-EnsureRegistryPath } | Should -Throw
            { Invoke-EnsureRegistryPath -Root 'HKLM' } | Should -Throw
        }

        It "Should accept valid Root values" {
            Mock Test-Path { $true } -ModuleName Registry

            { Invoke-EnsureRegistryPath -Root 'HKLM' -Path 'Software\Test' } | Should -Not -Throw
            { Invoke-EnsureRegistryPath -Root 'HKCU' -Path 'Software\Test' } | Should -Not -Throw
        }

        It "Should reject invalid Root values" {
            { Invoke-EnsureRegistryPath -Root 'INVALID' -Path 'Software\Test' } | Should -Throw
        }
    }

    Context "Invoke-OnEachUserHive Basic Tests" {
        It "Should require ScriptBlock parameter" {
            { Invoke-OnEachUserHive } | Should -Throw
        }

        It "Should accept ScriptBlock parameter" {
            # Mock all the helper functions to avoid Windows-specific operations
            Mock Get-AllSIDs { @() } -ModuleName Registry
            Mock Get-LoadedUserHives { @() } -ModuleName Registry
            Mock Get-UnloadedUserHives { @() } -ModuleName Registry

            $ScriptBlock = { param($Hive) }
            { Invoke-OnEachUserHive -ScriptBlock $ScriptBlock } | Should -Not -Throw
        }
    }

    Context "Cross-Platform Considerations" {
        It "Should handle non-Windows platforms gracefully" {
            if ($IsLinux -or $IsMacOS) {
                # On non-Windows platforms, registry operations should be mockable
                Mock Test-Path { $false } -ModuleName Registry

                { Test-RegistryKey -Path 'HKLM:\Software\Test' -Key 'TestKey' } | Should -Not -Throw
            }
        }
    }
}
