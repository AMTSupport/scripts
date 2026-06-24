BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/Environment.psm1" }

Describe 'Test-IsNableRunner Tests' {
    Context 'Basic Functionality' {
        It 'Should return False when not running in N-able context' {
            $Result = Test-IsNableRunner
            
            $Result | Should -Be $false
        }
    }
}