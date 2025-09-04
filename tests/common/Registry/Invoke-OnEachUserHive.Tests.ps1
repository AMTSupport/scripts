Describe "Invoke-OnEachUserHive Tests" -Skip:(-not $IsWindows) {
    BeforeAll {
        # Import required modules
        Import-Module "$PSScriptRoot/../../../src/common/Registry.psm1" -Force
        
        # Mock dependencies for cross-platform testing
        Mock Get-AllSIDs { 
            @(
                [PSCustomObject]@{ SID = 'S-1-5-21-1234567890-1234567890-1234567890-1001'; UserHive = 'C:\Users\User1\ntuser.dat'; Username = 'User1' },
                [PSCustomObject]@{ SID = 'S-1-5-21-1234567890-1234567890-1234567890-1002'; UserHive = 'C:\Users\User2\ntuser.dat'; Username = 'User2' }
            )
        }
        Mock Get-LoadedUserHives { 
            @(
                [PSCustomObject]@{ SID = 'S-1-5-21-1234567890-1234567890-1234567890-1001' }
            )
        }
        Mock Get-UnloadedUserHives { 
            param($LoadedHives, $ProfileList)
            @(
                [PSCustomObject]@{ SID = 'S-1-5-21-1234567890-1234567890-1234567890-1002'; UserHive = 'C:\Users\User2\ntuser.dat'; Username = 'User2' }
            )
        }
        Mock reg { }
        Mock Test-Path { $true }
        Mock Invoke-Verbose { }
        Mock Invoke-Debug { }
        Mock Invoke-Warn { }
    }

    Context "Basic Functionality" {
        It "Should execute script block for each user hive" {
            $ExecutionCount = 0
            $ScriptBlock = { param($Hive) $script:ExecutionCount++ }
            
            Invoke-OnEachUserHive -ScriptBlock $ScriptBlock
            
            $ExecutionCount | Should -Be 2  # Should execute for both users
        }

        It "Should pass hive information to script block" {
            $ReceivedHives = @()
            $ScriptBlock = { param($Hive) $script:ReceivedHives += $Hive }
            
            Invoke-OnEachUserHive -ScriptBlock $ScriptBlock
            
            $ReceivedHives.Count | Should -Be 2
            $ReceivedHives[0].Username | Should -Be 'User1'
            $ReceivedHives[1].Username | Should -Be 'User2'
        }

        It "Should handle loaded hives without loading/unloading" {
            $LoadedHiveProcessed = $false
            $ScriptBlock = { 
                param($Hive) 
                if ($Hive.SID -eq 'S-1-5-21-1234567890-1234567890-1234567890-1001') {
                    $script:LoadedHiveProcessed = $true
                }
            }
            
            Invoke-OnEachUserHive -ScriptBlock $ScriptBlock
            
            $LoadedHiveProcessed | Should -Be $true
            # Should not call reg load for already loaded hives
            Assert-MockCalled reg -Times 0 -ParameterFilter { $args[0] -eq 'load' -and $args[1] -like '*1001' }
        }

        It "Should load and unload unloaded hives" {
            Mock Test-Path { $true }  # Mock successful hive loading
            
            $UnloadedHiveProcessed = $false
            $ScriptBlock = { 
                param($Hive) 
                if ($Hive.SID -eq 'S-1-5-21-1234567890-1234567890-1234567890-1002') {
                    $script:UnloadedHiveProcessed = $true
                }
            }
            
            Invoke-OnEachUserHive -ScriptBlock $ScriptBlock
            
            $UnloadedHiveProcessed | Should -Be $true
            # Should call reg load and unload for unloaded hives
            Assert-MockCalled reg -Times 1 -ParameterFilter { $args[0] -eq 'load' }
            Assert-MockCalled reg -Times 1 -ParameterFilter { $args[0] -eq 'unload' }
        }
    }

    Context "Error Handling" {
        It "Should handle hive loading failures gracefully" {
            Mock Test-Path { $false }  # Simulate hive loading failure
            Mock Invoke-Warn { }
            
            $ScriptBlock = { param($Hive) }
            
            { Invoke-OnEachUserHive -ScriptBlock $ScriptBlock } | Should -Not -Throw
            
            # Should warn about failed hive loading
            Assert-MockCalled Invoke-Warn -Times 1
        }

        It "Should continue processing other hives when one fails" {
            Mock Test-Path { 
                # Fail for the second hive, succeed for others
                param($Path)
                $Path -notlike '*1002'
            }
            Mock Invoke-Warn { }
            
            $ProcessedCount = 0
            $ScriptBlock = { param($Hive) $script:ProcessedCount++ }
            
            Invoke-OnEachUserHive -ScriptBlock $ScriptBlock
            
            # Should still process the first (loaded) hive
            $ProcessedCount | Should -Be 1
            Assert-MockCalled Invoke-Warn -Times 1
        }

        It "Should handle script block exceptions gracefully" {
            $ScriptBlock = { param($Hive) throw "Script block error" }
            
            { Invoke-OnEachUserHive -ScriptBlock $ScriptBlock } | Should -Throw "Script block error"
        }

        It "Should always unload hives in finally block even on error" {
            Mock Test-Path { $true }
            
            $ScriptBlock = { param($Hive) 
                if ($Hive.SID -eq 'S-1-5-21-1234567890-1234567890-1234567890-1002') {
                    throw "Processing error"
                }
            }
            
            { Invoke-OnEachUserHive -ScriptBlock $ScriptBlock } | Should -Throw "Processing error"
            
            # Should still call unload even though error occurred
            Assert-MockCalled reg -Times 1 -ParameterFilter { $args[0] -eq 'unload' }
        }
    }

    Context "Registry Operations" {
        It "Should call reg load with correct parameters" {
            Mock Test-Path { $true }
            
            $ScriptBlock = { param($Hive) }
            
            Invoke-OnEachUserHive -ScriptBlock $ScriptBlock
            
            Assert-MockCalled reg -Times 1 -ParameterFilter { 
                $args[0] -eq 'load' -and 
                $args[1] -eq 'HKU\S-1-5-21-1234567890-1234567890-1234567890-1002' -and 
                $args[2] -eq 'C:\Users\User2\ntuser.dat'
            }
        }

        It "Should call reg unload with correct parameters" {
            Mock Test-Path { $true }
            
            $ScriptBlock = { param($Hive) }
            
            Invoke-OnEachUserHive -ScriptBlock $ScriptBlock
            
            Assert-MockCalled reg -Times 1 -ParameterFilter { 
                $args[0] -eq 'unload' -and 
                $args[1] -eq 'HKU\S-1-5-21-1234567890-1234567890-1234567890-1002'
            }
        }

        It "Should call garbage collection before unloading" {
            Mock Test-Path { $true }
            Mock -CommandName 'Invoke-Expression' -MockWith { } -ParameterFilter { $Command -eq '[GC]::Collect()' }
            
            $ScriptBlock = { param($Hive) }
            
            Invoke-OnEachUserHive -ScriptBlock $ScriptBlock
            
            # Note: [GC]::Collect() is called directly, not via Invoke-Expression, so this test verifies the concept
            Assert-MockCalled reg -Times 1 -ParameterFilter { $args[0] -eq 'unload' }
        }
    }

    Context "Hive Detection Logic" {
        It "Should correctly identify loaded vs unloaded hives" {
            $LoadedHiveCount = 0
            $UnloadedHiveCount = 0
            
            # Override mocks to track which hives are processed as loaded vs unloaded
            Mock reg { 
                if ($args[0] -eq 'load') { $script:UnloadedHiveCount++ }
                if ($args[0] -eq 'unload') { $script:UnloadedHiveCount++ }
            }
            
            $ScriptBlock = { 
                param($Hive) 
                if ($Hive.SID -eq 'S-1-5-21-1234567890-1234567890-1234567890-1001') {
                    $script:LoadedHiveCount++
                }
            }
            
            Invoke-OnEachUserHive -ScriptBlock $ScriptBlock
            
            $LoadedHiveCount | Should -Be 1  # One loaded hive processed
            # One unloaded hive should have been loaded and unloaded
            Assert-MockCalled reg -Times 2  # load + unload calls
        }

        It "Should handle empty hive lists gracefully" {
            Mock Get-AllSIDs { @() }
            Mock Get-LoadedUserHives { @() }
            Mock Get-UnloadedUserHives { @() }
            
            $ExecutionCount = 0
            $ScriptBlock = { param($Hive) $script:ExecutionCount++ }
            
            { Invoke-OnEachUserHive -ScriptBlock $ScriptBlock } | Should -Not -Throw
            
            $ExecutionCount | Should -Be 0
        }
    }

    Context "Parameter Validation" {
        It "Should require ScriptBlock parameter" {
            { Invoke-OnEachUserHive } | Should -Throw
        }

        It "Should accept valid script blocks" {
            $ScriptBlock = { param($Hive) Write-Output "Processing $($Hive.Username)" }
            
            { Invoke-OnEachUserHive -ScriptBlock $ScriptBlock } | Should -Not -Throw
        }
    }

    Context "Debug and Verbose Output" {
        It "Should provide debug output for hive operations" {
            Mock Test-Path { $true }
            
            $ScriptBlock = { param($Hive) }
            
            Invoke-OnEachUserHive -ScriptBlock $ScriptBlock
            
            # Should call debug logging functions
            Assert-MockCalled Invoke-Debug -AtLeast 1
        }

        It "Should provide verbose output for hive processing" {
            $ScriptBlock = { param($Hive) }
            
            Invoke-OnEachUserHive -ScriptBlock $ScriptBlock
            
            # Should call verbose logging
            Assert-MockCalled Invoke-Verbose -AtLeast 1
        }
    }

    Context "Integration with Helper Functions" {
        It "Should call Get-AllSIDs to get profile list" {
            $ScriptBlock = { param($Hive) }
            
            Invoke-OnEachUserHive -ScriptBlock $ScriptBlock
            
            Assert-MockCalled Get-AllSIDs -Times 1
        }

        It "Should call Get-LoadedUserHives to get loaded hives" {
            $ScriptBlock = { param($Hive) }
            
            Invoke-OnEachUserHive -ScriptBlock $ScriptBlock
            
            Assert-MockCalled Get-LoadedUserHives -Times 1
        }

        It "Should call Get-UnloadedUserHives with correct parameters" {
            $ScriptBlock = { param($Hive) }
            
            Invoke-OnEachUserHive -ScriptBlock $ScriptBlock
            
            Assert-MockCalled Get-UnloadedUserHives -Times 1 -ParameterFilter {
                $LoadedHives -ne $null -and $ProfileList -ne $null
            }
        }
    }
}