BeforeDiscovery {
    Import-Module "$PSScriptRoot/../../../src/common/Windows.psm1"
}

Describe 'Get-LastSyncTime Tests' -Skip:($IsWindows -eq $false) -Fixture {
    Context 'Basic Functionality' {
        It 'Should return a DateTime object' {
            $Result = Get-LastSyncTime

            $Result | Should -BeOfType [DateTime]
        }

        It 'Should parse valid w32tm output correctly' {
            $Result = Get-LastSyncTime
            $Result.Year | Should -Not -Be 1970
        }
    }
}
