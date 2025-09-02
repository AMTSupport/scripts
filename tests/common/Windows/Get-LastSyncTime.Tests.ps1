BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/Windows.psm1" }

Describe 'Get-LastSyncTime Tests' {
    Context 'Basic Functionality' {
        It 'Should return a DateTime object' {
            $Result = Get-LastSyncTime
            
            $Result | Should -BeOfType [DateTime]
        }

        It 'Should return Unix epoch when w32tm fails or returns unparseable data' {
            # Mock w32tm to return invalid data
            Mock w32tm { return 'Invalid output' } -ModuleName Windows
            
            $Result = Get-LastSyncTime
            
            $Expected = Get-Date -Year 1970 -Month 1 -Day 1
            $Result.Year | Should -Be $Expected.Year
            $Result.Month | Should -Be $Expected.Month
            $Result.Day | Should -Be $Expected.Day
        }

        It 'Should parse valid w32tm output correctly' {
            # Mock w32tm to return valid output
            $MockOutput = @(
                'Other line',
                'Last Successful Sync Time: 1/15/2024 10:30:45 AM',
                'Another line'
            )
            Mock w32tm { return $MockOutput } -ModuleName Windows
            
            $Result = Get-LastSyncTime
            
            $Result.Year | Should -Be 2024
            $Result.Month | Should -Be 1
            $Result.Day | Should -Be 15
            $Result.Hour | Should -Be 10
            $Result.Minute | Should -Be 30
        }

        It 'Should handle various datetime formats' {
            # Test different valid datetime formats that w32tm might return
            $TestFormats = @(
                'Last Successful Sync Time: 12/25/2023 2:15:30 PM',
                'Last Successful Sync Time: 1/1/2024 12:00:00 AM',
                'Last Successful Sync Time: 6/15/2023 11:45:22 PM'
            )
            
            foreach ($Format in $TestFormats) {
                Mock w32tm { return $Format } -ModuleName Windows
                
                $Result = Get-LastSyncTime
                $Result | Should -BeOfType [DateTime]
                $Result.Year | Should -BeGreaterThan 2020
            }
        }
    }

    Context 'Error Handling' {
        It 'Should handle w32tm command not found' {
            # Mock w32tm to throw an error (command not found)
            Mock w32tm { throw 'Command not found' } -ModuleName Windows
            
            $Result = Get-LastSyncTime
            
            $Expected = Get-Date -Year 1970 -Month 1 -Day 1
            $Result.Year | Should -Be $Expected.Year
            $Result.Month | Should -Be $Expected.Month
            $Result.Day | Should -Be $Expected.Day
        }

        It 'Should handle empty w32tm output' {
            Mock w32tm { return @() } -ModuleName Windows
            
            $Result = Get-LastSyncTime
            
            $Expected = Get-Date -Year 1970 -Month 1 -Day 1
            $Result.Year | Should -Be $Expected.Year
        }

        It 'Should handle malformed datetime strings' {
            $MalformedOutputs = @(
                'Last Successful Sync Time: Invalid Date',
                'Last Successful Sync Time: 13/50/2024 25:70:90 XM',
                'Last Successful Sync Time: Not a date at all'
            )
            
            foreach ($BadOutput in $MalformedOutputs) {
                Mock w32tm { return $BadOutput } -ModuleName Windows
                
                $Result = Get-LastSyncTime
                
                $Expected = Get-Date -Year 1970 -Month 1 -Day 1
                $Result.Year | Should -Be $Expected.Year
            }
        }
    }

    Context 'Regex Pattern Validation' {
        It 'Should match expected w32tm output format' {
            $ValidPatterns = @(
                'Last Successful Sync Time: 1/15/2024 10:30:45 AM',
                'Last Successful Sync Time: 12/31/2023 11:59:59 PM',
                'Last Successful Sync Time: 6/1/2024 1:05:22 AM'
            )
            
            $Regex = '^Last Successful Sync Time: (?<DateTime>[\d/:APM\s]+)$'
            
            foreach ($Pattern in $ValidPatterns) {
                $Pattern | Should -Match $Regex
            }
        }

        It 'Should not match invalid patterns' {
            $InvalidPatterns = @(
                'Different line format',
                'Last Sync Time: 1/15/2024 10:30:45 AM',  # Missing "Successful"
                'Last Successful Sync Time:',  # Missing datetime
                '  Last Successful Sync Time: 1/15/2024 10:30:45 AM'  # Leading spaces
            )
            
            $Regex = '^Last Successful Sync Time: (?<DateTime>[\d/:APM\s]+)$'
            
            foreach ($Pattern in $InvalidPatterns) {
                $Pattern | Should -Not -Match $Regex
            }
        }
    }
}