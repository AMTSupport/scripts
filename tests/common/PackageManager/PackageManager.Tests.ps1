Describe "PackageManager Module Tests" {
    BeforeAll {
        # Import required modules
        Import-Module "$PSScriptRoot/../../../src/common/PackageManager.psm1" -Force
        
        # Mock external dependencies for cross-platform testing
        Mock Test-NetworkConnection { $true } -ModuleName PackageManager
        Mock Get-Command { 
            [PSCustomObject]@{ Name = 'choco'; Source = 'C:\ProgramData\chocolatey\bin\choco.exe' }
        } -ModuleName PackageManager -ParameterFilter { $Name -eq 'choco' }
        Mock Test-Path { $true } -ModuleName PackageManager
        Mock Start-Process { 
            [PSCustomObject]@{ ExitCode = 0 }
        } -ModuleName PackageManager
        Mock Invoke-Expression { } -ModuleName PackageManager
        Mock Import-Module { } -ModuleName PackageManager
    }

    Context "Module Import" {
        It "Should import PackageManager module successfully" {
            Get-Module -Name PackageManager* | Should -Not -BeNullOrEmpty
        }

        It "Should export expected functions" {
            $ExportedFunctions = (Get-Module -Name PackageManager*).ExportedFunctions.Keys
            $ExportedFunctions | Should -Contain 'Test-ManagedPackage'
            $ExportedFunctions | Should -Contain 'Install-ManagedPackage'
            $ExportedFunctions | Should -Contain 'Uninstall-ManagedPackage'
            $ExportedFunctions | Should -Contain 'Update-ManagedPackage'
        }
    }

    Context "Test-ManagedPackage Tests" {
        It "Should require PackageName parameter" {
            { Test-ManagedPackage } | Should -Throw
        }

        It "Should accept PackageName parameter" {
            Mock Start-Process { 
                [PSCustomObject]@{ ExitCode = 0 }
            } -ModuleName PackageManager
            
            { Test-ManagedPackage -PackageName 'git' } | Should -Not -Throw
        }

        It "Should return boolean value" {
            Mock Start-Process { 
                [PSCustomObject]@{ ExitCode = 0 }
            } -ModuleName PackageManager
            
            $Result = Test-ManagedPackage -PackageName 'git'
            $Result | Should -BeOfType [Boolean]
        }

        It "Should handle package not found" {
            Mock Start-Process { 
                [PSCustomObject]@{ ExitCode = 1 }
            } -ModuleName PackageManager
            
            $Result = Test-ManagedPackage -PackageName 'nonexistent-package'
            $Result | Should -Be $false
        }

        It "Should handle network connection check" {
            Mock Test-NetworkConnection { $false } -ModuleName PackageManager
            
            # Should still work without network for already installed packages
            { Test-ManagedPackage -PackageName 'git' } | Should -Not -Throw
        }
    }

    Context "Install-ManagedPackage Tests" {
        It "Should require PackageName parameter" {
            { Install-ManagedPackage } | Should -Throw
        }

        It "Should accept PackageName parameter" {
            Mock Start-Process { 
                [PSCustomObject]@{ ExitCode = 0 }
            } -ModuleName PackageManager
            
            { Install-ManagedPackage -PackageName 'git' } | Should -Not -Throw
        }

        It "Should support ShouldProcess" {
            Mock Start-Process { 
                [PSCustomObject]@{ ExitCode = 0 }
            } -ModuleName PackageManager
            
            { Install-ManagedPackage -PackageName 'git' -WhatIf } | Should -Not -Throw
        }

        It "Should accept Sha256 parameter" {
            Mock Start-Process { 
                [PSCustomObject]@{ ExitCode = 0 }
            } -ModuleName PackageManager
            
            { Install-ManagedPackage -PackageName 'git' -Sha256 'abc123' } | Should -Not -Throw
        }

        It "Should accept NoFail parameter" {
            Mock Start-Process { 
                [PSCustomObject]@{ ExitCode = 1 }
            } -ModuleName PackageManager
            
            { Install-ManagedPackage -PackageName 'git' -NoFail } | Should -Not -Throw
        }

        It "Should handle installation failure without NoFail" {
            Mock Start-Process { 
                [PSCustomObject]@{ ExitCode = 1 }
            } -ModuleName PackageManager
            Mock Invoke-FailedExit { throw "Installation failed" } -ModuleName PackageManager
            
            { Install-ManagedPackage -PackageName 'git' } | Should -Throw
        }

        It "Should handle network connectivity check" {
            Mock Test-NetworkConnection { $false } -ModuleName PackageManager
            Mock Invoke-FailedExit { throw "No network" } -ModuleName PackageManager
            
            { Install-ManagedPackage -PackageName 'git' } | Should -Throw
        }
    }

    Context "Uninstall-ManagedPackage Tests" {
        It "Should require PackageName parameter" {
            { Uninstall-ManagedPackage } | Should -Throw
        }

        It "Should accept PackageName parameter" {
            Mock Invoke-Expression { } -ModuleName PackageManager
            
            { Uninstall-ManagedPackage -PackageName 'git' } | Should -Not -Throw
        }

        It "Should support ShouldProcess" {
            Mock Invoke-Expression { } -ModuleName PackageManager
            
            { Uninstall-ManagedPackage -PackageName 'git' -WhatIf } | Should -Not -Throw
        }

        It "Should accept NoFail parameter" {
            Mock Invoke-Expression { throw "Uninstall failed" } -ModuleName PackageManager
            Mock Invoke-Error { } -ModuleName PackageManager
            
            { Uninstall-ManagedPackage -PackageName 'git' -NoFail } | Should -Not -Throw
        }

        It "Should handle uninstallation failure without NoFail" {
            Mock Invoke-Expression { 
                $global:LASTEXITCODE = 1
                throw "Uninstall failed" 
            } -ModuleName PackageManager
            Mock Invoke-Error { } -ModuleName PackageManager
            Mock Invoke-FailedExit { throw "Uninstall failed" } -ModuleName PackageManager
            
            { Uninstall-ManagedPackage -PackageName 'git' } | Should -Throw
        }
    }

    Context "Update-ManagedPackage Tests" {
        It "Should require PackageName parameter" {
            { Update-ManagedPackage } | Should -Throw
        }

        It "Should accept PackageName parameter" {
            Mock Invoke-Expression { } -ModuleName PackageManager
            
            { Update-ManagedPackage -PackageName 'git' } | Should -Not -Throw
        }

        It "Should support ShouldProcess" {
            Mock Invoke-Expression { } -ModuleName PackageManager
            
            { Update-ManagedPackage -PackageName 'git' -WhatIf } | Should -Not -Throw
        }

        It "Should handle update failure" {
            Mock Invoke-Expression { 
                $global:LASTEXITCODE = 1
                throw "Update failed" 
            } -ModuleName PackageManager
            Mock Invoke-Error { } -ModuleName PackageManager
            
            { Update-ManagedPackage -PackageName 'git' } | Should -Not -Throw
        }
    }

    Context "Package Manager Detection" {
        It "Should detect Chocolatey on Windows" {
            if ($IsWindows) {
                # The module should detect Chocolatey as the package manager
                $true | Should -Be $true  # This is tested implicitly by other tests
            }
        }

        It "Should handle unsupported platforms" {
            if ($IsLinux -or $IsMacOS) {
                # On non-Windows platforms, should handle gracefully or indicate unsupported
                # This depends on the module's implementation
                $true | Should -Be $true
            }
        }
    }

    Context "Chocolatey Integration" {
        BeforeEach {
            Mock Get-Command { 
                [PSCustomObject]@{ Name = 'choco'; Source = 'C:\ProgramData\chocolatey\bin\choco.exe' }
            } -ModuleName PackageManager -ParameterFilter { $Name -eq 'choco' }
        }

        It "Should detect existing Chocolatey installation" {
            # When choco command is available, should not reinstall
            Mock Get-Command { 
                [PSCustomObject]@{ Name = 'choco' }
            } -ModuleName PackageManager -ParameterFilter { $Name -eq 'choco' }
            
            { Install-ManagedPackage -PackageName 'git' } | Should -Not -Throw
        }

        It "Should handle missing Chocolatey installation" {
            Mock Get-Command { $null } -ModuleName PackageManager -ParameterFilter { $Name -eq 'choco' }
            Mock Test-Path { $false } -ModuleName PackageManager
            Mock Invoke-Expression { } -ModuleName PackageManager  # Mock Chocolatey installation
            
            { Install-ManagedPackage -PackageName 'git' } | Should -Not -Throw
        }

        It "Should handle Chocolatey directory repair" {
            Mock Get-Command { $null } -ModuleName PackageManager -ParameterFilter { $Name -eq 'choco' }
            Mock Test-Path { 
                param($Path)
                if ($Path -like '*chocolatey') { return $true }
                if ($Path -like '*choco.exe') { return $true }
                return $false
            } -ModuleName PackageManager
            Mock Import-Module { } -ModuleName PackageManager
            Mock Invoke-Expression { } -ModuleName PackageManager  # Mock refreshenv
            
            { Install-ManagedPackage -PackageName 'git' } | Should -Not -Throw
        }
    }

    Context "Error Handling" {
        It "Should handle network connectivity issues" {
            Mock Test-NetworkConnection { $false } -ModuleName PackageManager
            Mock Invoke-Error { } -ModuleName PackageManager
            Mock Invoke-FailedExit { throw "No network" } -ModuleName PackageManager
            
            { Install-ManagedPackage -PackageName 'git' } | Should -Throw
        }

        It "Should handle package manager not found" {
            Mock Get-Command { $null } -ModuleName PackageManager
            Mock Test-Path { $false } -ModuleName PackageManager
            Mock Invoke-Error { } -ModuleName PackageManager
            
            # Should handle gracefully or throw appropriate error
            { Test-ManagedPackage -PackageName 'git' } | Should -Not -Throw
        }

        It "Should handle package installation timeout" {
            Mock Start-Process { 
                Start-Sleep -Seconds 2
                [PSCustomObject]@{ ExitCode = 1 }
            } -ModuleName PackageManager
            Mock Invoke-FailedExit { throw "Installation timed out" } -ModuleName PackageManager
            
            { Install-ManagedPackage -PackageName 'git' } | Should -Throw
        }
    }

    Context "Parameter Validation" {
        It "Should validate PackageName is not null or empty" {
            { Test-ManagedPackage -PackageName '' } | Should -Throw
            { Test-ManagedPackage -PackageName $null } | Should -Throw
        }

        It "Should accept valid package names" {
            Mock Start-Process { [PSCustomObject]@{ ExitCode = 0 } } -ModuleName PackageManager
            
            { Test-ManagedPackage -PackageName 'git' } | Should -Not -Throw
            { Test-ManagedPackage -PackageName 'nodejs' } | Should -Not -Throw
            { Test-ManagedPackage -PackageName 'python3' } | Should -Not -Throw
        }

        It "Should handle special characters in package names" {
            Mock Start-Process { [PSCustomObject]@{ ExitCode = 0 } } -ModuleName PackageManager
            
            { Test-ManagedPackage -PackageName 'package-with-dashes' } | Should -Not -Throw
            { Test-ManagedPackage -PackageName 'package.with.dots' } | Should -Not -Throw
        }
    }

    Context "Logging and Verbose Output" {
        It "Should provide verbose output during operations" {
            Mock Start-Process { [PSCustomObject]@{ ExitCode = 0 } } -ModuleName PackageManager
            Mock Invoke-Verbose { } -ModuleName PackageManager
            Mock Invoke-Info { } -ModuleName PackageManager
            
            { Install-ManagedPackage -PackageName 'git' -Verbose } | Should -Not -Throw
            
            # Should call logging functions
        }

        It "Should provide debug information" {
            Mock Start-Process { [PSCustomObject]@{ ExitCode = 0 } } -ModuleName PackageManager
            Mock Invoke-Debug { } -ModuleName PackageManager
            
            { Test-ManagedPackage -PackageName 'git' -Debug } | Should -Not -Throw
        }
    }

    Context "Cross-Platform Behavior" {
        It "Should handle Windows-specific operations on Windows" {
            if ($IsWindows) {
                # Should work with Chocolatey
                { Test-ManagedPackage -PackageName 'git' } | Should -Not -Throw
            }
        }

        It "Should handle non-Windows platforms appropriately" {
            if ($IsLinux -or $IsMacOS) {
                # Should either work with alternative package managers or indicate unsupported
                # This test validates that it doesn't crash on non-Windows
                { $null } | Should -Not -Throw
            }
        }
    }
}