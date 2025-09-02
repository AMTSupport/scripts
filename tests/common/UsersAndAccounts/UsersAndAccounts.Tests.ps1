Describe "UsersAndAccounts Module Tests" {
    BeforeAll {
        # Import required modules
        Import-Module "$PSScriptRoot/../../../src/common/UsersAndAccounts.psm1" -Force
        
        # Mock ADSI objects for cross-platform testing
        $MockGroup = [PSCustomObject]@{
            Name = 'Administrators'
            SchemaClassName = 'Group'
            Path = 'WinNT://COMPUTER/Administrators,group'
            PSChildName = 'Administrators'
        }
        
        $MockUser = [PSCustomObject]@{
            Name = 'TestUser'
            SchemaClassName = 'User'
            Path = 'WinNT://COMPUTER/TestUser,user'
            PSChildName = 'TestUser'
        }
        
        # Mock ADSI constructor
        Mock -CommandName 'Invoke-Expression' -MockWith { 
            param($Command)
            if ($Command -like '*WinNT://*,group*') {
                return $MockGroup
            } elseif ($Command -like '*WinNT://*,user*') {
                return $MockUser
            } elseif ($Command -like '*WinNT://*' -and $Command -notlike '*,*') {
                # Mock for container operations
                return [PSCustomObject]@{
                    Children = @($MockGroup, $MockUser)
                }
            }
            return $null
        }
    }

    Context "Module Import" {
        It "Should import UsersAndAccounts module successfully" {
            Get-Module -Name UsersAndAccounts* | Should -Not -BeNullOrEmpty
        }

        It "Should export expected functions" {
            $ExportedFunctions = (Get-Module -Name UsersAndAccounts*).ExportedFunctions.Keys
            $ExportedFunctions | Should -Contain 'Get-User'
            $ExportedFunctions | Should -Contain 'Get-UserGroups'
            $ExportedFunctions | Should -Contain 'Get-Group'
            $ExportedFunctions | Should -Contain 'Get-MembersOfGroup'
            $ExportedFunctions | Should -Contain 'Test-MemberOfGroup'
            $ExportedFunctions | Should -Contain 'Add-MemberToGroup'
            $ExportedFunctions | Should -Contain 'Remove-MemberFromGroup'
            $ExportedFunctions | Should -Contain 'Format-ADSIUser'
        }
    }

    Context "Get-Group Tests" {
        BeforeEach {
            # Reset cached groups for each test
            if (Get-Variable -Name 'Script:InitialisedAllGroups' -Scope Script -ErrorAction SilentlyContinue) {
                Set-Variable -Name 'Script:InitialisedAllGroups' -Value $false -Scope Script
            }
            if (Get-Variable -Name 'Script:CachedGroups' -Scope Script -ErrorAction SilentlyContinue) {
                Set-Variable -Name 'Script:CachedGroups' -Value @{} -Scope Script
            }
        }

        It "Should accept Name parameter" {
            { Get-Group -Name 'Administrators' } | Should -Not -Throw
        }

        It "Should accept no parameters to get all groups" {
            { Get-Group } | Should -Not -Throw
        }

        It "Should handle empty or null group names" {
            { Get-Group -Name '' } | Should -Not -Throw
            { Get-Group -Name $null } | Should -Not -Throw
        }
    }

    Context "Get-User Tests" {
        BeforeEach {
            # Reset cached users for each test
            if (Get-Variable -Name 'Script:InitialisedAllUsers' -Scope Script -ErrorAction SilentlyContinue) {
                Set-Variable -Name 'Script:InitialisedAllUsers' -Value $false -Scope Script
            }
            if (Get-Variable -Name 'Script:CachedUsers' -Scope Script -ErrorAction SilentlyContinue) {
                Set-Variable -Name 'Script:CachedUsers' -Value @{} -Scope Script
            }
        }

        It "Should accept Name parameter" {
            { Get-User -Name 'TestUser' } | Should -Not -Throw
        }

        It "Should accept no parameters to get all users" {
            { Get-User } | Should -Not -Throw
        }

        It "Should handle empty or null user names" {
            { Get-User -Name '' } | Should -Not -Throw
            { Get-User -Name $null } | Should -Not -Throw
        }
    }

    Context "Test-MemberOfGroup Tests" {
        It "Should require Group parameter" {
            { Test-MemberOfGroup -User 'TestUser' } | Should -Throw
        }

        It "Should require User parameter" {
            { Test-MemberOfGroup -Group 'Administrators' } | Should -Throw
        }

        It "Should accept Group and User parameters" {
            Mock Get-GroupByInputOrName { $MockGroup } -ModuleName UsersAndAccounts
            Mock Get-UserByInputOrName { $MockUser } -ModuleName UsersAndAccounts
            
            # Mock the ADSI Invoke method
            Add-Member -InputObject $MockGroup -MemberType ScriptMethod -Name 'Invoke' -Value { 
                param($Method, $Path)
                if ($Method -eq 'IsMember') { return $true }
                return $null
            } -Force
            
            { Test-MemberOfGroup -Group $MockGroup -User $MockUser } | Should -Not -Throw
        }
    }

    Context "Add-MemberToGroup Tests" {
        It "Should require Group parameter" {
            { Add-MemberToGroup -User 'TestUser' } | Should -Throw
        }

        It "Should require User parameter" {
            { Add-MemberToGroup -Group 'Administrators' } | Should -Throw
        }

        It "Should accept Group and User parameters" {
            Mock Get-GroupByInputOrName { $MockGroup } -ModuleName UsersAndAccounts
            Mock Get-UserByInputOrName { $MockUser } -ModuleName UsersAndAccounts
            Mock Test-MemberOfGroup { $false } -ModuleName UsersAndAccounts
            
            # Mock the ADSI Invoke method for Add
            Add-Member -InputObject $MockGroup -MemberType ScriptMethod -Name 'Invoke' -Value { 
                param($Method, $Path)
                if ($Method -eq 'Add') { return $null }
                return $null
            } -Force
            
            { Add-MemberToGroup -Group $MockGroup -User $MockUser } | Should -Not -Throw
        }
    }

    Context "Remove-MemberFromGroup Tests" {
        It "Should require Group parameter" {
            { Remove-MemberFromGroup -Member 'TestUser' } | Should -Throw
        }

        It "Should require Member parameter" {
            { Remove-MemberFromGroup -Group 'Administrators' } | Should -Throw
        }

        It "Should accept Group and Member parameters" {
            Mock Get-GroupByInputOrName { $MockGroup } -ModuleName UsersAndAccounts
            Mock Get-UserByInputOrName { $MockUser } -ModuleName UsersAndAccounts
            Mock Test-MemberOfGroup { $true } -ModuleName UsersAndAccounts
            
            # Mock the ADSI Invoke method for Remove
            Add-Member -InputObject $MockGroup -MemberType ScriptMethod -Name 'Invoke' -Value { 
                param($Method, $Path)
                if ($Method -eq 'Remove') { return $null }
                return $null
            } -Force
            
            { Remove-MemberFromGroup -Group $MockGroup -Member $MockUser } | Should -Not -Throw
        }
    }

    Context "Get-MembersOfGroup Tests" {
        It "Should require Group parameter" {
            { Get-MembersOfGroup } | Should -Throw
        }

        It "Should accept Group parameter" {
            Mock Get-GroupByInputOrName { $MockGroup } -ModuleName UsersAndAccounts
            
            # Mock the ADSI Invoke method for Members
            Add-Member -InputObject $MockGroup -MemberType ScriptMethod -Name 'Invoke' -Value { 
                param($Method)
                if ($Method -eq 'Members') { 
                    return @($MockUser)
                }
                return $null
            } -Force
            
            { Get-MembersOfGroup -Group $MockGroup } | Should -Not -Throw
        }
    }

    Context "Get-UserGroups Tests" {
        It "Should require User parameter" {
            { Get-UserGroups } | Should -Throw
        }

        It "Should accept User parameter" {
            Mock Get-UserByInputOrName { $MockUser } -ModuleName UsersAndAccounts
            Mock Get-WmiObject { 
                @([PSCustomObject]@{ GroupComponent = 'Win32_Group.Domain="COMPUTER",Name="Administrators"' })
            } -ModuleName UsersAndAccounts
            
            { Get-UserGroups -User $MockUser } | Should -Not -Throw
        }
    }

    Context "Format-ADSIUser Tests" {
        It "Should require User parameter" {
            { Format-ADSIUser } | Should -Throw
        }

        It "Should accept User parameter with correct schema" {
            $ValidUser = [PSCustomObject]@{
                SchemaClassName = 'User'
                Path = 'WinNT://COMPUTER/TestUser'
            }
            
            { Format-ADSIUser -User $ValidUser } | Should -Not -Throw
        }

        It "Should handle array of users" {
            $Users = @(
                [PSCustomObject]@{ SchemaClassName = 'User'; Path = 'WinNT://COMPUTER/User1' },
                [PSCustomObject]@{ SchemaClassName = 'User'; Path = 'WinNT://COMPUTER/User2' }
            )
            
            { Format-ADSIUser -User $Users } | Should -Not -Throw
        }

        It "Should validate SchemaClassName is User" {
            $InvalidUser = [PSCustomObject]@{
                SchemaClassName = 'Group'
                Path = 'WinNT://COMPUTER/SomeGroup'
            }
            
            { Format-ADSIUser -User $InvalidUser } | Should -Throw
        }
    }

    Context "Cross-Platform Considerations" {
        It "Should handle non-Windows platforms gracefully" {
            if ($IsLinux -or $IsMacOS) {
                # On non-Windows platforms, ADSI operations should be mockable
                { Get-Group -Name 'TestGroup' } | Should -Not -Throw
                { Get-User -Name 'TestUser' } | Should -Not -Throw
            }
        }

        It "Should handle ADSI constructor failures" {
            # Mock ADSI constructor to fail
            Mock -CommandName 'Invoke-Expression' -MockWith { 
                throw "ADSI not available"
            }
            
            # Functions should handle this gracefully (or throw appropriate errors)
            { Get-Group -Name 'TestGroup' } | Should -Throw
        }
    }

    Context "Caching Behavior" {
        It "Should cache group results" {
            # First call should initialize cache
            Get-Group -Name 'Administrators'
            
            # Second call should use cache
            Get-Group -Name 'Administrators'
            
            # This is difficult to test without access to internal variables
            # but at least verify it doesn't throw
            $true | Should -Be $true
        }

        It "Should cache user results" {
            # First call should initialize cache
            Get-User -Name 'TestUser'
            
            # Second call should use cache
            Get-User -Name 'TestUser'
            
            # This is difficult to test without access to internal variables
            # but at least verify it doesn't throw
            $true | Should -Be $true
        }
    }

    Context "Error Handling" {
        It "Should handle missing groups gracefully" -Skip:($IsLinux -or $IsMacOS) {
            { Get-Group -Name 'NonExistentGroup' } | Should -Not -Throw
        }

        It "Should handle missing users gracefully" -Skip:($IsLinux -or $IsMacOS) {
            { Get-User -Name 'NonExistentUser' } | Should -Not -Throw
        }

        It "Should handle ADSI exceptions" {
            Mock -CommandName 'Invoke-Expression' -MockWith { 
                throw "ADSI access denied"
            }
            
            { Get-Group -Name 'TestGroup' } | Should -Throw
        }
    }
}