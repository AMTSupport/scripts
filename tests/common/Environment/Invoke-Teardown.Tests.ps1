BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/Environment.psm1" }

Describe 'Invoke-Teardown Tests' {
    BeforeEach {
        $Global:PSDefaultParameterValues['*:ErrorAction'] = 'Stop'
        $Global:PSDefaultParameterValues['*:WarningAction'] = 'Continue'
        $Global:PSDefaultParameterValues['*:InformationAction'] = 'Continue'
        $Global:PSDefaultParameterValues['*:Verbose'] = $true
        $Global:PSDefaultParameterValues['*:Debug'] = $true
        $Global:PSDefaultParameterValues['*-Module:Verbose'] = $true
    }

    Context 'Parameter Value Cleanup' {
        It 'Should remove all expected parameters from PSDefaultParameterValues' {
            $ExpectedKeys = @(
                '*:ErrorAction',
                '*:WarningAction', 
                '*:InformationAction',
                '*:Verbose',
                '*:Debug',
                '*-Module:Verbose'
            )
            
            # Verify all keys exist before teardown
            foreach ($Key in $ExpectedKeys) {
                $Global:PSDefaultParameterValues.ContainsKey($Key) | Should -Be $true
            }
            
            InModuleScope Environment {
                Invoke-Teardown
            }
            
            # Verify all keys are removed after teardown
            foreach ($Key in $ExpectedKeys) {
                $Global:PSDefaultParameterValues.ContainsKey($Key) | Should -Be $false
            }
        }
    }

    Context 'Multiple Teardown Calls' {
        It 'Should handle being called multiple times without error' {
            InModuleScope Environment {
                { Invoke-Teardown } | Should -Not -Throw
                { Invoke-Teardown } | Should -Not -Throw
                { Invoke-Teardown } | Should -Not -Throw
            }
        }

        It 'Should not throw when keys do not exist' {
            $Global:PSDefaultParameterValues.Remove('*:ErrorAction')
            $Global:PSDefaultParameterValues.Remove('*:Verbose')
            
            InModuleScope Environment {
                { Invoke-Teardown } | Should -Not -Throw
            }
        }
    }

    Context 'Integration with Invoke-Setup' {
        It 'Should clean up all values set by Invoke-Setup' {
            InModuleScope Environment {
                Invoke-Setup
            }
            
            $Global:PSDefaultParameterValues.ContainsKey('*:ErrorAction') | Should -Be $true
            $Global:PSDefaultParameterValues.ContainsKey('*:WarningAction') | Should -Be $true
            $Global:PSDefaultParameterValues.ContainsKey('*:InformationAction') | Should -Be $true
            
            InModuleScope Environment {
                Invoke-Teardown
            }
            
            $Global:PSDefaultParameterValues.ContainsKey('*:ErrorAction') | Should -Be $false
            $Global:PSDefaultParameterValues.ContainsKey('*:WarningAction') | Should -Be $false
            $Global:PSDefaultParameterValues.ContainsKey('*:InformationAction') | Should -Be $false
            $Global:PSDefaultParameterValues.ContainsKey('*:Verbose') | Should -Be $false
            $Global:PSDefaultParameterValues.ContainsKey('*:Debug') | Should -Be $false
            $Global:PSDefaultParameterValues.ContainsKey('*-Module:Verbose') | Should -Be $false
        }
    }

    Context 'Selective Removal' {
        It 'Should only remove specific keys and leave others intact' {
            $Global:PSDefaultParameterValues['Get-Process:Name'] = 'powershell'
            $Global:PSDefaultParameterValues['Test-Custom:Param'] = 'value'
            
            InModuleScope Environment {
                Invoke-Teardown
            }
            
            $Global:PSDefaultParameterValues.ContainsKey('*:ErrorAction') | Should -Be $false
            $Global:PSDefaultParameterValues.ContainsKey('*:WarningAction') | Should -Be $false
            
            $Global:PSDefaultParameterValues.ContainsKey('Get-Process:Name') | Should -Be $true
            $Global:PSDefaultParameterValues.ContainsKey('Test-Custom:Param') | Should -Be $true
            
            $Global:PSDefaultParameterValues.Remove('Get-Process:Name')
            $Global:PSDefaultParameterValues.Remove('Test-Custom:Param')
        }
    }
}