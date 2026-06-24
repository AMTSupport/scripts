Describe "Ensure Module Tests" {
    BeforeAll {
        Import-Module "$PSScriptRoot/../../../src/common/Ensure.psm1" -Force
    }

    Context "Invoke-EnsureAdministrator Tests" {
        It "Should handle cross-platform scenarios" {
            if ($IsLinux -or $IsMacOS) {
                { Invoke-EnsureAdministrator } | Should -Not -Throw
            }
        }
    }

    Context "Invoke-EnsureUser Tests" {
        It "Should handle cross-platform scenarios" {
            if ($IsLinux -or $IsMacOS) {
                { Invoke-EnsureUser } | Should -Not -Throw
            }
        }
    }

    Context 'Invoke-EnsureModule Tests' {
        BeforeEach {
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
        }
        It 'Should require Modules parameter' {
            { Invoke-EnsureModule } | Should -Throw
        }

        It 'Should accept string module names' {
            Mock Get-Module { $null } -ModuleName Ensure
            Mock Find-PSResource { [PSCustomObject]@{ Name = 'TestModule'; Version = '1.0.0' } } -ModuleName Ensure
            Mock Install-PSResource { } -ModuleName Ensure
            Mock Import-Module { } -ModuleName Ensure

            { Invoke-EnsureModule -Modules @('TestModule') } | Should -Not -Throw

            Should -Invoke Find-PSResource -Times 1 -ModuleName Ensure
            Should -Invoke Install-PSResource -Times 1 -ModuleName Ensure
        }

        It 'Should accept hashtable module specifications' {
            Mock Get-Module { $null } -ModuleName Ensure
            Mock Find-PSResource { [PSCustomObject]@{ Name = 'TestModule'; Version = '2.0.0' } } -ModuleName Ensure
            Mock Install-PSResource { } -ModuleName Ensure
            Mock Import-Module { } -ModuleName Ensure

            $ModuleSpec = @{
                Name           = 'TestModule'
                MinimumVersion = '2.0.0'
            }

            { Invoke-EnsureModule -Modules @($ModuleSpec) } | Should -Not -Throw

            Should -Invoke Find-PSResource -Times 1 -ModuleName Ensure
            Should -Invoke Install-PSResource -Times 1 -ModuleName Ensure
        }

        It 'Should handle already imported modules' {
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'TestModule'; Version = '1.0.0' }
            } -ModuleName Ensure

            { Invoke-EnsureModule -Modules @('TestModule') } | Should -Not -Throw

            # Should not attempt to install if already imported
            Should -Invoke Install-PSResource -Times 0 -ModuleName Ensure
        }

        It 'Should handle local module paths' {
            Mock Test-Path { $true } -ModuleName Ensure
            Mock Import-Module { } -ModuleName Ensure

            $LocalPath = '/path/to/local/module.psm1'
            { Invoke-EnsureModule -Modules @($LocalPath) } | Should -Not -Throw

            Should -Invoke Import-Module -Times 1 -ModuleName Ensure
        }

        It 'Should handle GitHub repository modules' {
            Mock Install-ModuleFromGitHub { '/temp/path/to/module' } -ModuleName Ensure
            Mock Import-Module { } -ModuleName Ensure

            $GitHubModule = 'owner/repo@main'
            { Invoke-EnsureModule -Modules @($GitHubModule) } | Should -Not -Throw

            Should -Invoke Install-ModuleFromGitHub -Times 1 -ModuleName Ensure
        }

        It 'Should handle module updates' {
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'TestModule'; Version = '1.0.0' }
            } -ModuleName Ensure
            Mock Update-PSResource { } -ModuleName Ensure
            Mock Import-Module { } -ModuleName Ensure

            $ModuleSpec = @{
                Name           = 'TestModule'
                MinimumVersion = '2.0.0'
            }

            { Invoke-EnsureModule -Modules @($ModuleSpec) } | Should -Not -Throw

            Should -Invoke Update-PSResource -Times 1 -ModuleName Ensure
        }

        It 'Should handle network connectivity issues' {
            Mock Test-NetworkConnection { $false } -ModuleName Ensure
            Mock Invoke-Warn { } -ModuleName Ensure

            { Invoke-EnsureModule -Modules @('TestModule') } | Should -Not -Throw

            Should -Invoke Invoke-Warn -Times 1 -ModuleName Ensure
            # Should not attempt installation without network
            Should -Invoke Install-PSResource -Times 0 -ModuleName Ensure
        }

        It 'Should handle NuGet package provider installation' {
            Mock Get-PackageProvider { throw 'NuGet not found' } -ModuleName Ensure
            Mock Install-PackageProvider { } -ModuleName Ensure
            Mock Set-PSRepository { } -ModuleName Ensure
            Mock Get-Module { $null } -ModuleName Ensure
            Mock Find-PSResource { [PSCustomObject]@{ Name = 'TestModule'; Version = '1.0.0' } } -ModuleName Ensure
            Mock Install-PSResource { } -ModuleName Ensure
            Mock Import-Module { } -ModuleName Ensure

            { Invoke-EnsureModule -Modules @('TestModule') } | Should -Not -Throw

            Should -Invoke Install-PackageProvider -Times 1 -ModuleName Ensure
            Should -Invoke Set-PSRepository -Times 1 -ModuleName Ensure
        }

        It 'Should validate module specifications' {
            $InvalidSpec = [PSCustomObject]@{ InvalidProperty = 'Value' }

            { Invoke-EnsureModule -Modules @($InvalidSpec) } | Should -Throw
        }

        It 'Should handle DontRemove flag' {
            Mock Get-Module { $null } -ModuleName Ensure
            Mock Find-PSResource { [PSCustomObject]@{ Name = 'TestModule'; Version = '1.0.0' } } -ModuleName Ensure
            Mock Install-PSResource { } -ModuleName Ensure
            Mock Import-Module { } -ModuleName Ensure

            $ModuleSpec = @{
                Name       = 'TestModule'
                DontRemove = $true
            }

            { Invoke-EnsureModule -Modules @($ModuleSpec) } | Should -Not -Throw
        }
    }

    Context 'Invoke-EnsureNetwork Tests' {
        BeforeEach {
            Mock netsh { } -ModuleName Ensure
            Mock Test-Connection { $true } -ModuleName Ensure
            Mock Get-NetConnectionProfile {
                [PSCustomObject]@{ IPv4Connectivity = 'Internet'; IPv6Connectivity = 'Internet' }
            } -ModuleName Ensure
        }
        BeforeEach {
            Mock Get-NetConnectionProfile {
                [PSCustomObject]@{ IPv4Connectivity = 'NoTraffic'; IPv6Connectivity = 'NoTraffic' }
            } -ModuleName Ensure
        }

        It 'Should accept Name parameter' {
            Mock netsh { } -ModuleName Ensure
            Mock Test-Connection { $true } -ModuleName Ensure
            Mock Invoke-WithinEphemeral {
                param($ScriptBlock)
                & $ScriptBlock
            } -ModuleName Ensure

            { Invoke-EnsureNetwork -Name 'TestNetwork' } | Should -Not -Throw
        }

        It 'Should accept optional Password parameter' {
            Mock netsh { } -ModuleName Ensure
            Mock Test-Connection { $true } -ModuleName Ensure
            Mock Invoke-WithinEphemeral {
                param($ScriptBlock)
                & $ScriptBlock
            } -ModuleName Ensure

            $SecurePassword = ConvertTo-SecureString 'password123' -AsPlainText -Force
            { Invoke-EnsureNetwork -Name 'TestNetwork' -Password $SecurePassword } | Should -Not -Throw
        }

        It 'Should detect existing network connection' {
            Mock Get-NetConnectionProfile {
                [PSCustomObject]@{ IPv4Connectivity = 'Internet'; IPv6Connectivity = 'Internet' }
            } -ModuleName Ensure
            Mock Invoke-Debug { } -ModuleName Ensure

            $Result = Invoke-EnsureNetwork -Name 'TestNetwork'

            $Result | Should -Be $false
            Should -Invoke Invoke-Debug -Times 1 -ModuleName Ensure
        }

        It 'Should setup network when no connection exists' {
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
            Should -Invoke netsh -Times 3 -ModuleName Ensure  # add profile, show profiles, connect
            Should -Invoke Test-Connection -Times 1 -ModuleName Ensure
        }

        It 'Should handle WhatIf parameter' {
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
            Should -Invoke netsh -Times 0 -ModuleName Ensure
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

            Should -Invoke Invoke-FailedExit -Times 1 -ModuleName Ensure
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
            Should -Invoke Out-File -Times 1 -ModuleName Ensure
            Should -Invoke netsh -Times 3 -ModuleName Ensure
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

            Should -Invoke Invoke-FailedExit -Times 1 -ModuleName Ensure
        }

        It "Should handle module import failures" {
            Mock Test-NetworkConnection { $true } -ModuleName Ensure
            Mock Get-Module { $null } -ModuleName Ensure
            Mock Find-PSResource { [PSCustomObject]@{ Name = 'TestModule'; Version = '1.0.0' } } -ModuleName Ensure
            Mock Install-PSResource { } -ModuleName Ensure
            Mock Import-Module { throw "Import failed" } -ModuleName Ensure
            Mock Invoke-FailedExit { throw "Module import failed" } -ModuleName Ensure

            { Invoke-EnsureModule -Modules @('TestModule') } | Should -Throw "Module import failed"

            Should -Invoke Invoke-FailedExit -Times 1 -ModuleName Ensure
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
}
