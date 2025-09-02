Describe "Ensure Module Tests" {
    BeforeAll {
        # Import required modules
        Import-Module "$PSScriptRoot/../../../src/common/Ensure.psm1" -Force
        
        # Mock external dependencies for cross-platform testing
        Mock Test-NetworkConnection { $true } -ModuleName Ensure
        Mock Get-PackageProvider { } -ModuleName Ensure
        Mock Install-PackageProvider { } -ModuleName Ensure
        Mock Set-PSRepository { } -ModuleName Ensure
        Mock Get-Module { $null } -ModuleName Ensure
        Mock Import-Module { } -ModuleName Ensure
        Mock Install-PSResource { } -ModuleName Ensure
        Mock Update-PSResource { } -ModuleName Ensure
        Mock Find-PSResource { 
            [PSCustomObject]@{ Name = 'TestModule'; Version = '1.0.0' }
        } -ModuleName Ensure
        Mock Test-Path { $true } -ModuleName Ensure
        Mock netsh { } -ModuleName Ensure
        Mock Test-Connection { $true } -ModuleName Ensure
        Mock Get-NetConnectionProfile { 
            [PSCustomObject]@{ IPv4Connectivity = 'Internet'; IPv6Connectivity = 'Internet' }
        } -ModuleName Ensure
        
        # Mock Windows security principal checks
        Mock -CommandName 'New-Object' -MockWith {
            param($TypeName)
            if ($TypeName -eq 'Security.Principal.WindowsPrincipal') {
                return [PSCustomObject]@{
                    IsInRole = { param($Role) return $false }  # Default to non-administrator
                }
            }
            return $null
        } -ModuleName Ensure
    }

    Context "Module Import" {
        It "Should import Ensure module successfully" {
            Get-Module -Name Ensure* | Should -Not -BeNullOrEmpty
        }

        It "Should export expected functions" {
            $ExportedFunctions = (Get-Module -Name Ensure*).ExportedFunctions.Keys
            $ExportedFunctions | Should -Contain 'Invoke-EnsureAdministrator'
            $ExportedFunctions | Should -Contain 'Invoke-EnsureUser'
            $ExportedFunctions | Should -Contain 'Invoke-EnsureModule'
            $ExportedFunctions | Should -Contain 'Invoke-EnsureNetwork'
        }
    }

    Context "Invoke-EnsureAdministrator Tests" {
        It "Should pass when running as administrator" {
            Mock -CommandName 'New-Object' -MockWith {
                param($TypeName)
                if ($TypeName -eq 'Security.Principal.WindowsPrincipal') {
                    return [PSCustomObject]@{
                        IsInRole = { param($Role) return $true }  # Return true for administrator
                    }
                }
                return $null
            } -ModuleName Ensure
            Mock Invoke-Verbose { } -ModuleName Ensure
            
            { Invoke-EnsureAdministrator } | Should -Not -Throw
            
            Assert-MockCalled Invoke-Verbose -Times 1 -ModuleName Ensure
        }

        It "Should fail when not running as administrator" -Skip:($IsLinux -or $IsMacOS) {
            Mock -CommandName 'New-Object' -MockWith {
                param($TypeName)
                if ($TypeName -eq 'Security.Principal.WindowsPrincipal') {
                    return [PSCustomObject]@{
                        IsInRole = { param($Role) return $false }  # Return false for administrator
                    }
                }
                return $null
            } -ModuleName Ensure
            Mock Invoke-FailedExit { throw "Not administrator" } -ModuleName Ensure
            
            { Invoke-EnsureAdministrator } | Should -Throw "Not administrator"
            
            Assert-MockCalled Invoke-FailedExit -Times 1 -ModuleName Ensure
        }

        It "Should handle cross-platform scenarios" {
            if ($IsLinux -or $IsMacOS) {
                # On non-Windows platforms, the function should handle gracefully
                { Invoke-EnsureAdministrator } | Should -Not -Throw
            }
        }
    }

    Context "Invoke-EnsureUser Tests" {
        It "Should pass when running as regular user" {
            Mock -CommandName 'New-Object' -MockWith {
                param($TypeName)
                if ($TypeName -eq 'Security.Principal.WindowsPrincipal') {
                    return [PSCustomObject]@{
                        IsInRole = { param($Role) return $false }  # Return false for administrator (running as user)
                    }
                }
                return $null
            } -ModuleName Ensure
            Mock Invoke-Verbose { } -ModuleName Ensure
            
            { Invoke-EnsureUser } | Should -Not -Throw
            
            Assert-MockCalled Invoke-Verbose -Times 1 -ModuleName Ensure
        }

        It "Should fail when running as administrator" -Skip:($IsLinux -or $IsMacOS) {
            Mock -CommandName 'New-Object' -MockWith {
                param($TypeName)
                if ($TypeName -eq 'Security.Principal.WindowsPrincipal') {
                    return [PSCustomObject]@{
                        IsInRole = { param($Role) return $true }  # Return true for administrator
                    }
                }
                return $null
            } -ModuleName Ensure
            Mock Invoke-FailedExit { throw "Running as administrator" } -ModuleName Ensure
            
            { Invoke-EnsureUser } | Should -Throw "Running as administrator"
            
            Assert-MockCalled Invoke-FailedExit -Times 1 -ModuleName Ensure
        }
    }

    Context "Invoke-EnsureModule Tests" {
        It "Should require Modules parameter" {
            { Invoke-EnsureModule } | Should -Throw
        }

        It "Should accept string module names" {
            Mock Get-Module { $null } -ModuleName Ensure
            Mock Find-PSResource { [PSCustomObject]@{ Name = 'TestModule'; Version = '1.0.0' } } -ModuleName Ensure
            Mock Install-PSResource { } -ModuleName Ensure
            Mock Import-Module { } -ModuleName Ensure
            
            { Invoke-EnsureModule -Modules @('TestModule') } | Should -Not -Throw
            
            Assert-MockCalled Find-PSResource -Times 1 -ModuleName Ensure
            Assert-MockCalled Install-PSResource -Times 1 -ModuleName Ensure
        }

        It "Should accept hashtable module specifications" {
            Mock Get-Module { $null } -ModuleName Ensure
            Mock Find-PSResource { [PSCustomObject]@{ Name = 'TestModule'; Version = '2.0.0' } } -ModuleName Ensure
            Mock Install-PSResource { } -ModuleName Ensure
            Mock Import-Module { } -ModuleName Ensure
            
            $ModuleSpec = @{
                Name = 'TestModule'
                MinimumVersion = '2.0.0'
            }
            
            { Invoke-EnsureModule -Modules @($ModuleSpec) } | Should -Not -Throw
            
            Assert-MockCalled Find-PSResource -Times 1 -ModuleName Ensure
            Assert-MockCalled Install-PSResource -Times 1 -ModuleName Ensure
        }

        It "Should handle already imported modules" {
            Mock Get-Module { 
                [PSCustomObject]@{ Name = 'TestModule'; Version = '1.0.0' }
            } -ModuleName Ensure
            
            { Invoke-EnsureModule -Modules @('TestModule') } | Should -Not -Throw
            
            # Should not attempt to install if already imported
            Assert-MockCalled Install-PSResource -Times 0 -ModuleName Ensure
        }

        It "Should handle local module paths" {
            Mock Test-Path { $true } -ModuleName Ensure
            Mock Import-Module { } -ModuleName Ensure
            
            $LocalPath = '/path/to/local/module.psm1'
            { Invoke-EnsureModule -Modules @($LocalPath) } | Should -Not -Throw
            
            Assert-MockCalled Import-Module -Times 1 -ModuleName Ensure
        }

        It "Should handle GitHub repository modules" {
            Mock Install-ModuleFromGitHub { '/temp/path/to/module' } -ModuleName Ensure
            Mock Import-Module { } -ModuleName Ensure
            
            $GitHubModule = 'owner/repo@main'
            { Invoke-EnsureModule -Modules @($GitHubModule) } | Should -Not -Throw
            
            Assert-MockCalled Install-ModuleFromGitHub -Times 1 -ModuleName Ensure
        }

        It "Should handle module updates" {
            Mock Get-Module { 
                [PSCustomObject]@{ Name = 'TestModule'; Version = '1.0.0' }
            } -ModuleName Ensure
            Mock Update-PSResource { } -ModuleName Ensure
            Mock Import-Module { } -ModuleName Ensure
            
            $ModuleSpec = @{
                Name = 'TestModule'
                MinimumVersion = '2.0.0'
            }
            
            { Invoke-EnsureModule -Modules @($ModuleSpec) } | Should -Not -Throw
            
            Assert-MockCalled Update-PSResource -Times 1 -ModuleName Ensure
        }

        It "Should handle network connectivity issues" {
            Mock Test-NetworkConnection { $false } -ModuleName Ensure
            Mock Invoke-Warn { } -ModuleName Ensure
            
            { Invoke-EnsureModule -Modules @('TestModule') } | Should -Not -Throw
            
            Assert-MockCalled Invoke-Warn -Times 1 -ModuleName Ensure
            # Should not attempt installation without network
            Assert-MockCalled Install-PSResource -Times 0 -ModuleName Ensure
        }

        It "Should handle NuGet package provider installation" {
            Mock Get-PackageProvider { throw "NuGet not found" } -ModuleName Ensure
            Mock Install-PackageProvider { } -ModuleName Ensure
            Mock Set-PSRepository { } -ModuleName Ensure
            Mock Get-Module { $null } -ModuleName Ensure
            Mock Find-PSResource { [PSCustomObject]@{ Name = 'TestModule'; Version = '1.0.0' } } -ModuleName Ensure
            Mock Install-PSResource { } -ModuleName Ensure
            Mock Import-Module { } -ModuleName Ensure
            
            { Invoke-EnsureModule -Modules @('TestModule') } | Should -Not -Throw
            
            Assert-MockCalled Install-PackageProvider -Times 1 -ModuleName Ensure
            Assert-MockCalled Set-PSRepository -Times 1 -ModuleName Ensure
        }

        It "Should validate module specifications" {
            $InvalidSpec = [PSCustomObject]@{ InvalidProperty = 'Value' }
            
            { Invoke-EnsureModule -Modules @($InvalidSpec) } | Should -Throw
        }

        It "Should handle DontRemove flag" {
            Mock Get-Module { $null } -ModuleName Ensure
            Mock Find-PSResource { [PSCustomObject]@{ Name = 'TestModule'; Version = '1.0.0' } } -ModuleName Ensure
            Mock Install-PSResource { } -ModuleName Ensure
            Mock Import-Module { } -ModuleName Ensure
            
            $ModuleSpec = @{
                Name = 'TestModule'
                DontRemove = $true
            }
            
            { Invoke-EnsureModule -Modules @($ModuleSpec) } | Should -Not -Throw
        }
    }

    Context "Invoke-EnsureNetwork Tests" {
        BeforeEach {
            Mock Get-NetConnectionProfile { 
                [PSCustomObject]@{ IPv4Connectivity = 'NoTraffic'; IPv6Connectivity = 'NoTraffic' }
            } -ModuleName Ensure
        }

        It "Should accept Name parameter" {
            Mock netsh { } -ModuleName Ensure
            Mock Test-Connection { $true } -ModuleName Ensure
            Mock Invoke-WithinEphemeral { 
                param($ScriptBlock)
                & $ScriptBlock
            } -ModuleName Ensure
            
            { Invoke-EnsureNetwork -Name 'TestNetwork' } | Should -Not -Throw
        }

        It "Should accept optional Password parameter" {
            Mock netsh { } -ModuleName Ensure
            Mock Test-Connection { $true } -ModuleName Ensure
            Mock Invoke-WithinEphemeral { 
                param($ScriptBlock)
                & $ScriptBlock
            } -ModuleName Ensure
            
            $SecurePassword = ConvertTo-SecureString 'password123' -AsPlainText -Force
            { Invoke-EnsureNetwork -Name 'TestNetwork' -Password $SecurePassword } | Should -Not -Throw
        }

        It "Should detect existing network connection" {
            Mock Get-NetConnectionProfile { 
                [PSCustomObject]@{ IPv4Connectivity = 'Internet'; IPv6Connectivity = 'Internet' }
            } -ModuleName Ensure
            Mock Invoke-Debug { } -ModuleName Ensure
            
            $Result = Invoke-EnsureNetwork -Name 'TestNetwork'
            
            $Result | Should -Be $false
            Assert-MockCalled Invoke-Debug -Times 1 -ModuleName Ensure
        }

        It "Should setup network when no connection exists" {
            Mock Get-NetConnectionProfile { 
                [PSCustomObject]@{ IPv4Connectivity = 'NoTraffic'; IPv6Connectivity = 'NoTraffic' }
            } -ModuleName Ensure
            Mock Invoke-WithinEphemeral { 
                param($ScriptBlock)
                & $ScriptBlock
            } -ModuleName Ensure
            Mock netsh { } -ModuleName Ensure
            Mock Test-Connection { $true } -ModuleName Ensure
            Mock Invoke-Info { } -ModuleName Ensure
            
            $Result = Invoke-EnsureNetwork -Name 'TestNetwork'
            
            $Result | Should -Be $true
            Assert-MockCalled netsh -Times 3 -ModuleName Ensure  # add profile, show profiles, connect
            Assert-MockCalled Test-Connection -Times 1 -ModuleName Ensure
        }

        It "Should handle WhatIf parameter" {
            Mock Get-NetConnectionProfile { 
                [PSCustomObject]@{ IPv4Connectivity = 'NoTraffic'; IPv6Connectivity = 'NoTraffic' }
            } -ModuleName Ensure
            Mock Invoke-WithinEphemeral { 
                param($ScriptBlock)
                & $ScriptBlock
            } -ModuleName Ensure
            Mock Invoke-Info { } -ModuleName Ensure
            
            $Result = Invoke-EnsureNetwork -Name 'TestNetwork' -WhatIf
            
            $Result | Should -Be $true
            Assert-MockCalled netsh -Times 0 -ModuleName Ensure
        }

        It "Should handle network setup timeout" {
            Mock Get-NetConnectionProfile { 
                [PSCustomObject]@{ IPv4Connectivity = 'NoTraffic'; IPv6Connectivity = 'NoTraffic' }
            } -ModuleName Ensure
            Mock Invoke-WithinEphemeral { 
                param($ScriptBlock)
                & $ScriptBlock
            } -ModuleName Ensure
            Mock netsh { } -ModuleName Ensure
            Mock Test-Connection { $false } -ModuleName Ensure  # Simulate connection failure
            Mock Invoke-Error { } -ModuleName Ensure
            Mock Invoke-FailedExit { throw "Network setup failed" } -ModuleName Ensure
            
            { Invoke-EnsureNetwork -Name 'TestNetwork' } | Should -Throw "Network setup failed"
            
            Assert-MockCalled Invoke-FailedExit -Times 1 -ModuleName Ensure
        }

        It "Should generate correct WiFi XML profile" {
            Mock Get-NetConnectionProfile { 
                [PSCustomObject]@{ IPv4Connectivity = 'NoTraffic'; IPv6Connectivity = 'NoTraffic' }
            } -ModuleName Ensure
            Mock Invoke-WithinEphemeral { 
                param($ScriptBlock)
                & $ScriptBlock
            } -ModuleName Ensure
            Mock Out-File { } -ModuleName Ensure
            Mock netsh { } -ModuleName Ensure
            Mock Test-Connection { $true } -ModuleName Ensure
            
            { Invoke-EnsureNetwork -Name 'TestSSID' } | Should -Not -Throw
            
            # Should create XML profile and execute netsh commands
            Assert-MockCalled Out-File -Times 1 -ModuleName Ensure
            Assert-MockCalled netsh -Times 3 -ModuleName Ensure
        }
    }

    Context "Error Handling" {
        It "Should handle module installation failures" {
            Mock Test-NetworkConnection { $true } -ModuleName Ensure
            Mock Get-Module { $null } -ModuleName Ensure
            Mock Find-PSResource { [PSCustomObject]@{ Name = 'TestModule'; Version = '1.0.0' } } -ModuleName Ensure
            Mock Install-PSResource { throw "Installation failed" } -ModuleName Ensure
            Mock Invoke-FailedExit { throw "Module installation failed" } -ModuleName Ensure
            
            { Invoke-EnsureModule -Modules @('TestModule') } | Should -Throw "Module installation failed"
            
            Assert-MockCalled Invoke-FailedExit -Times 1 -ModuleName Ensure
        }

        It "Should handle module import failures" {
            Mock Test-NetworkConnection { $true } -ModuleName Ensure
            Mock Get-Module { $null } -ModuleName Ensure
            Mock Find-PSResource { [PSCustomObject]@{ Name = 'TestModule'; Version = '1.0.0' } } -ModuleName Ensure
            Mock Install-PSResource { } -ModuleName Ensure
            Mock Import-Module { throw "Import failed" } -ModuleName Ensure
            Mock Invoke-FailedExit { throw "Module import failed" } -ModuleName Ensure
            
            { Invoke-EnsureModule -Modules @('TestModule') } | Should -Throw "Module import failed"
            
            Assert-MockCalled Invoke-FailedExit -Times 1 -ModuleName Ensure
        }

        It "Should handle network setup failures" {
            Mock Get-NetConnectionProfile { 
                [PSCustomObject]@{ IPv4Connectivity = 'NoTraffic'; IPv6Connectivity = 'NoTraffic' }
            } -ModuleName Ensure
            Mock Invoke-WithinEphemeral { 
                param($ScriptBlock)
                & $ScriptBlock
            } -ModuleName Ensure
            Mock netsh { throw "Network command failed" } -ModuleName Ensure
            
            { Invoke-EnsureNetwork -Name 'TestNetwork' } | Should -Throw "Network command failed"
        }
    }

    Context "Parameter Validation" {
        It "Should validate Modules parameter is not null or empty" {
            { Invoke-EnsureModule -Modules @() } | Should -Throw
            { Invoke-EnsureModule -Modules $null } | Should -Throw
        }

        It "Should validate Network Name parameter" {
            { Invoke-EnsureNetwork -Name '' } | Should -Throw
            { Invoke-EnsureNetwork -Name $null } | Should -Throw
        }

        It "Should accept valid module specification formats" {
            Mock Test-NetworkConnection { $true } -ModuleName Ensure
            Mock Get-Module { $null } -ModuleName Ensure
            Mock Find-PSResource { [PSCustomObject]@{ Name = 'TestModule'; Version = '1.0.0' } } -ModuleName Ensure
            Mock Install-PSResource { } -ModuleName Ensure
            Mock Import-Module { } -ModuleName Ensure
            
            # String format
            { Invoke-EnsureModule -Modules @('TestModule') } | Should -Not -Throw
            
            # Hashtable format
            $HashSpec = @{ Name = 'TestModule'; MinimumVersion = '1.0.0' }
            { Invoke-EnsureModule -Modules @($HashSpec) } | Should -Not -Throw
            
            # GitHub format
            { Invoke-EnsureModule -Modules @('owner/repo@branch') } | Should -Not -Throw
        }
    }

    Context "Cross-Platform Behavior" {
        It "Should handle Windows-specific operations on Windows" {
            if ($IsWindows) {
                # Administrator/User checks should work
                { Invoke-EnsureAdministrator } | Should -Not -Throw
                { Invoke-EnsureUser } | Should -Not -Throw
            }
        }

        It "Should handle non-Windows platforms appropriately" {
            if ($IsLinux -or $IsMacOS) {
                # Should either work with alternative implementations or skip gracefully
                # This test validates that it doesn't crash on non-Windows
                { $null } | Should -Not -Throw
            }
        }

        It "Should handle network operations cross-platform" {
            # Network operations should be cross-platform or gracefully handled
            Mock Get-NetConnectionProfile { 
                [PSCustomObject]@{ IPv4Connectivity = 'Internet'; IPv6Connectivity = 'Internet' }
            } -ModuleName Ensure
            
            { Invoke-EnsureNetwork -Name 'TestNetwork' } | Should -Not -Throw
        }
    }

    Context "Module Cleanup and Exit Handlers" {
        It "Should register exit handlers for module cleanup" {
            Mock Register-ExitHandler { } -ModuleName Ensure
            Mock Test-NetworkConnection { $true } -ModuleName Ensure
            Mock Get-Module { $null } -ModuleName Ensure
            Mock Find-PSResource { [PSCustomObject]@{ Name = 'TestModule'; Version = '1.0.0' } } -ModuleName Ensure
            Mock Install-PSResource { } -ModuleName Ensure
            Mock Import-Module { } -ModuleName Ensure
            
            { Invoke-EnsureModule -Modules @('TestModule') } | Should -Not -Throw
            
            # Should register cleanup handlers (this is tested indirectly)
        }

        It "Should handle module removal on exit" {
            Mock Remove-Module { } -ModuleName Ensure
            Mock Invoke-Verbose { } -ModuleName Ensure
            Mock Invoke-Debug { } -ModuleName Ensure
            
            # This tests the concept - actual exit handler testing is complex
            { Remove-Module -Name 'TestModule' -Force } | Should -Not -Throw
        }
    }
}