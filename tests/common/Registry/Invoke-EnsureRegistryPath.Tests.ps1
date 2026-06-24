Describe "Invoke-EnsureRegistryPath Tests" -Skip:(-not $IsWindows) {
    BeforeAll {
        # Import required modules
        Import-Module "$PSScriptRoot/../../../src/common/Registry.psm1" -Force

        # Mock dependencies for cross-platform testing
        Mock Test-Path { $false }
        Mock New-Item {
            [PSCustomObject]@{
                Name = 'MockedKey'
                PSPath = "TestRegistry::$Path"
            }
        }
        Mock Join-Path {
            param($Path, $ChildPath)
            if ($Path.EndsWith(':')) {
                return "$Path\$ChildPath"
            }
            return "$Path\$ChildPath"
        }
    }

    Context "Basic Functionality" {
        It "Should create registry path with HKLM root" {
            Mock Test-Path { $false }

            { Invoke-EnsureRegistryPath -Root 'HKLM' -Path 'Software\TestPath' } | Should -Not -Throw

            Should -Invoke Test-Path -Exactly 2 -Scope It
            Should -Invoke New-Item -Exactly 2 -Scope It
        }

        It "Should create registry path with HKCU root" {
            Mock Test-Path { $false }

            { Invoke-EnsureRegistryPath -Root 'HKCU' -Path 'Software\TestPath' } | Should -Not -Throw

            Should -Invoke Test-Path -Exactly 2 -Scope It
            Should -Invoke New-Item -Exactly 2 -Scope It
        }

        It "Should handle existing registry paths" {
            Mock Test-Path { $true }

            { Invoke-EnsureRegistryPath -Root 'HKLM' -Path 'Software\ExistingPath' } | Should -Not -Throw

            Should -Invoke Test-Path -AtLeast 1 -Scope It
            Should -Invoke New-Item -Exactly 0 -Scope It
        }

        It "Should handle nested registry paths" {
            Mock Test-Path { $false }

            { Invoke-EnsureRegistryPath -Root 'HKLM' -Path 'Software\Level1\Level2\Level3' } | Should -Not -Throw

            Should -Invoke Test-Path -AtLeast 3 -Scope It
            Should -Invoke New-Item -AtLeast 3 -Scope It
        }
    }

    Context "ShouldProcess Support" {
        It "Should support WhatIf parameter" {
            Mock Test-Path { $false }

            { Invoke-EnsureRegistryPath -Root 'HKLM' -Path 'Software\TestPath' -WhatIf } | Should -Not -Throw

            # When WhatIf is used, New-Item should not be called
            Should -Invoke New-Item -Exactly 0 -Scope It
        }

        It "Should support Confirm parameter" {
            Mock Test-Path { $false }

            { Invoke-EnsureRegistryPath -Root 'HKLM' -Path 'Software\TestPath' -Confirm:$false } | Should -Not -Throw

            Should -Invoke New-Item -AtLeast 1 -Scope It
        }
    }

    Context "Parameter Validation" {
        It "Should accept valid Root values" {
            Mock Test-Path { $true }

            { Invoke-EnsureRegistryPath -Root 'HKLM' -Path 'Software' } | Should -Not -Throw
            { Invoke-EnsureRegistryPath -Root 'HKCU' -Path 'Software' } | Should -Not -Throw
        }

        It "Should reject invalid Root values" {
            { Invoke-EnsureRegistryPath -Root 'INVALID' -Path 'Software' } | Should -Throw
        }

        It "Should handle empty path segments" {
            Mock Test-Path { $false }

            { Invoke-EnsureRegistryPath -Root 'HKLM' -Path 'Software\\TestPath' } | Should -Not -Throw

            # Should filter out empty segments
            Should -Invoke Test-Path -AtLeast 1 -Scope It
        }

        It "Should handle paths with leading/trailing slashes" {
            Mock Test-Path { $false }

            { Invoke-EnsureRegistryPath -Root 'HKLM' -Path '\Software\TestPath\' } | Should -Not -Throw

            Should -Invoke Test-Path -AtLeast 1 -Scope It
        }
    }

    Context "Error Handling" {
        It "Should handle New-Item failures gracefully" {
            Mock Test-Path { $false }
            Mock New-Item { throw "Access denied" }

            { Invoke-EnsureRegistryPath -Root 'HKLM' -Path 'Software\TestPath' } | Should -Throw "Access denied"
        }

        It "Should handle Test-Path failures gracefully" {
            Mock Test-Path { throw "Registry key not accessible" }

            { Invoke-EnsureRegistryPath -Root 'HKLM' -Path 'Software\TestPath' } | Should -Throw "Registry key not accessible"
        }
    }

    Context "Integration with Registry Provider" {
        It "Should build correct registry paths for HKLM" {
            Mock Test-Path { $false }
            Mock New-Item { }

            Invoke-EnsureRegistryPath -Root 'HKLM' -Path 'Software\TestPath'

            Should -Invoke Test-Path -ParameterFilter { $Path -like 'HKLM:*' }
            Should -Invoke New-Item -ParameterFilter { $Path -like 'HKLM:*' }
        }

        It "Should build correct registry paths for HKCU" {
            Mock Test-Path { $false }
            Mock New-Item { }

            Invoke-EnsureRegistryPath -Root 'HKCU' -Path 'Software\TestPath'

            Should -Invoke Test-Path -ParameterFilter { $Path -like 'HKCU:*' }
            Should -Invoke New-Item -ParameterFilter { $Path -like 'HKCU:*' }
        }
    }
}
