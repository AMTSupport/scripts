BeforeDiscovery { 
    Import-Module "$PSScriptRoot/../../../src/common/Windows.psm1"
}

Describe 'Sync-Time Tests' {
    BeforeAll {
        # Mock all external dependencies for cross-platform testing
        Mock w32tm { return 'Sending resync command to local computer' } -ModuleName Windows
        Mock Get-LastSyncTime { return (Get-Date).AddHours(-1) } -ModuleName Windows
    }
    
    BeforeEach {
        # Reset mocks for each test to ensure clean state
        Mock w32tm { return 'Sending resync command to local computer' } -ModuleName Windows
        Mock Get-LastSyncTime { return (Get-Date).AddHours(-1) } -ModuleName Windows
    }

    Context 'Basic Functionality' {
        It 'Should return a Boolean value' {
            # Mock Get-LastSyncTime to return a recent time (no sync needed)
            Mock Get-LastSyncTime { return (Get-Date).AddHours(-1) } -ModuleName Windows
            
            $Result = Sync-Time
            
            $Result | Should -BeOfType [Boolean]
        }

        It 'Should return False when last sync time is within threshold' {
            # Mock Get-LastSyncTime to return a recent time (within default 7 days)
            Mock Get-LastSyncTime { return (Get-Date).AddDays(-2) } -ModuleName Windows
            
            $Result = Sync-Time
            
            $Result | Should -Be $false
        }

        It 'Should return True and trigger resync when last sync time exceeds threshold' {
            # Mock Get-LastSyncTime to return an old time (beyond default 7 days)
            Mock Get-LastSyncTime { return (Get-Date).AddDays(-10) } -ModuleName Windows
            Mock w32tm { return 'Sending resync command to local computer' } -ModuleName Windows
            
            $Result = Sync-Time
            
            $Result | Should -Be $true
            
            # Verify w32tm was called with correct parameters
            Assert-MockCalled w32tm -ModuleName Windows -ParameterFilter { $args -contains '/resync' -and $args -contains '/force' }
        }

        It 'Should respect custom threshold parameter' {
            # Mock Get-LastSyncTime to return a time 2 days ago
            Mock Get-LastSyncTime { return (Get-Date).AddDays(-2) } -ModuleName Windows
            Mock w32tm { return 'Sending resync command to local computer' } -ModuleName Windows
            
            # Set threshold to 1 day - should trigger resync
            $CustomThreshold = New-TimeSpan -Days 1
            $Result = Sync-Time -Threshold $CustomThreshold
            
            $Result | Should -Be $true
            Assert-MockCalled w32tm -ModuleName Windows -ParameterFilter { $args -contains '/resync' -and $args -contains '/force' }
        }

        It 'Should handle different threshold units' {
            # Mock Get-LastSyncTime to return a time 3 hours ago
            Mock Get-LastSyncTime { return (Get-Date).AddHours(-3) } -ModuleName Windows
            Mock w32tm { return 'Sending resync command to local computer' } -ModuleName Windows
            
            # Test with hours threshold
            $HoursThreshold = New-TimeSpan -Hours 2
            $Result = Sync-Time -Threshold $HoursThreshold
            
            $Result | Should -Be $true
            Assert-MockCalled w32tm -ModuleName Windows -ParameterFilter { $args -contains '/resync' -and $args -contains '/force' }
        }
    }

    Context 'Default Parameters' {
        It 'Should use 7 days as default threshold' {
            # Mock Get-LastSyncTime to return exactly 7 days ago
            Mock Get-LastSyncTime { return (Get-Date).AddDays(-7).AddMinutes(-1) } -ModuleName Windows
            Mock w32tm { return 'Sending resync command to local computer' } -ModuleName Windows
            
            $Result = Sync-Time
            
            $Result | Should -Be $true
            Assert-MockCalled w32tm -ModuleName Windows
        }

        It 'Should not sync when exactly at threshold' {
            # Mock Get-LastSyncTime to return exactly 7 days ago
            Mock Get-LastSyncTime { return (Get-Date).AddDays(-7) } -ModuleName Windows
            
            $Result = Sync-Time
            
            $Result | Should -Be $false
        }
    }

    Context 'Edge Cases' {
        It 'Should handle future last sync time' {
            # Mock Get-LastSyncTime to return a future time (system clock skew)
            Mock Get-LastSyncTime { return (Get-Date).AddDays(1) } -ModuleName Windows
            
            $Result = Sync-Time
            
            # Should not sync when last sync is in the future
            $Result | Should -Be $false
        }

        It 'Should handle Unix epoch last sync time' {
            # Mock Get-LastSyncTime to return Unix epoch (never synced)
            Mock Get-LastSyncTime { return (Get-Date -Year 1970 -Month 1 -Day 1) } -ModuleName Windows
            Mock w32tm { return 'Sending resync command to local computer' } -ModuleName Windows
            
            $Result = Sync-Time
            
            $Result | Should -Be $true
            Assert-MockCalled w32tm -ModuleName Windows
        }

        It 'Should handle very large threshold values' {
            # Mock Get-LastSyncTime to return a very old time
            Mock Get-LastSyncTime { return (Get-Date).AddDays(-365) } -ModuleName Windows
            
            # Set a very large threshold (2 years)
            $LargeThreshold = New-TimeSpan -Days 730
            $Result = Sync-Time -Threshold $LargeThreshold
            
            $Result | Should -Be $false
        }

        It 'Should handle very small threshold values' {
            # Mock Get-LastSyncTime to return a time 5 minutes ago
            Mock Get-LastSyncTime { return (Get-Date).AddMinutes(-5) } -ModuleName Windows
            Mock w32tm { return 'Sending resync command to local computer' } -ModuleName Windows
            
            # Set a very small threshold (1 minute)
            $SmallThreshold = New-TimeSpan -Minutes 1
            $Result = Sync-Time -Threshold $SmallThreshold
            
            $Result | Should -Be $true
            Assert-MockCalled w32tm -ModuleName Windows
        }
    }

    Context 'Error Handling' {
        It 'Should handle w32tm resync command failure' {
            # Mock Get-LastSyncTime to return an old time
            Mock Get-LastSyncTime { return (Get-Date).AddDays(-10) } -ModuleName Windows
            Mock w32tm { throw 'Access denied' } -ModuleName Windows
            
            # Should still return true even if w32tm fails (indicates sync was attempted)
            $Result = Sync-Time
            
            $Result | Should -Be $true
            Assert-MockCalled w32tm -ModuleName Windows
        }

        It 'Should handle Get-LastSyncTime returning null' {
            Mock Get-LastSyncTime { return $null } -ModuleName Windows
            
            # This test depends on how the function handles null from Get-LastSyncTime
            # If it throws, we catch it; if it handles gracefully, we verify behavior
            { $Result = Sync-Time } | Should -Not -Throw
        }
    }

    Context 'Parameter Validation' {
        It 'Should validate threshold parameter is not null or empty' {
            { Sync-Time -Threshold $null } | Should -Throw
        }

        It 'Should accept zero timespan threshold' {
            # Mock Get-LastSyncTime to return current time
            Mock Get-LastSyncTime { return (Get-Date) } -ModuleName Windows
            
            $ZeroThreshold = New-TimeSpan -Seconds 0
            $Result = Sync-Time -Threshold $ZeroThreshold
            
            $Result | Should -Be $false
        }

        It 'Should accept negative timespan threshold' {
            # Mock Get-LastSyncTime to return current time
            Mock Get-LastSyncTime { return (Get-Date) } -ModuleName Windows
            Mock w32tm { return 'Sending resync command to local computer' } -ModuleName Windows
            
            $NegativeThreshold = New-TimeSpan -Days -1
            $Result = Sync-Time -Threshold $NegativeThreshold
            
            # With negative threshold, any sync time should trigger resync
            $Result | Should -Be $true
        }
    }

    Context 'Integration with Get-LastSyncTime' {
        It 'Should call Get-LastSyncTime to determine sync status' {
            Mock Get-LastSyncTime { return (Get-Date).AddDays(-2) } -ModuleName Windows
            
            $Result = Sync-Time
            
            Assert-MockCalled Get-LastSyncTime -ModuleName Windows -Exactly 1
        }
    }
}