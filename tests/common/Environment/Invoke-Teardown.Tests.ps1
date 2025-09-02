BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/Environment.psm1" }

Describe 'Invoke-Teardown Tests' {
    BeforeAll {
        # Save original values
        $Script:OriginalPSDefaultParameterValues = $Global:PSDefaultParameterValues.Clone()
    }

    AfterAll {
        # Restore original values
        $Global:PSDefaultParameterValues = $Script:OriginalPSDefaultParameterValues
    }

    BeforeEach {
        # Set up test values before each test
        $Global:PSDefaultParameterValues['*:ErrorAction'] = 'Stop'
        $Global:PSDefaultParameterValues['*:WarningAction'] = 'Continue'
        $Global:PSDefaultParameterValues['*:InformationAction'] = 'Continue'
        $Global:PSDefaultParameterValues['*:Verbose'] = $true
        $Global:PSDefaultParameterValues['*:Debug'] = $true
        $Global:PSDefaultParameterValues['*-Module:Verbose'] = $true
    }

    Context 'Parameter Value Cleanup' {
        It 'Should remove ErrorAction from PSDefaultParameterValues' {
            $Global:PSDefaultParameterValues.ContainsKey('*:ErrorAction') | Should -Be $true
            
            InModuleScope Environment {
                Invoke-Teardown
            }
            
            $Global:PSDefaultParameterValues.ContainsKey('*:ErrorAction') | Should -Be $false
        }

        It 'Should remove WarningAction from PSDefaultParameterValues' {
            $Global:PSDefaultParameterValues.ContainsKey('*:WarningAction') | Should -Be $true
            
            InModuleScope Environment {
                Invoke-Teardown
            }
            
            $Global:PSDefaultParameterValues.ContainsKey('*:WarningAction') | Should -Be $false
        }

        It 'Should remove InformationAction from PSDefaultParameterValues' {
            $Global:PSDefaultParameterValues.ContainsKey('*:InformationAction') | Should -Be $true
            
            InModuleScope Environment {
                Invoke-Teardown
            }
            
            $Global:PSDefaultParameterValues.ContainsKey('*:InformationAction') | Should -Be $false
        }

        It 'Should remove Verbose from PSDefaultParameterValues' {
            $Global:PSDefaultParameterValues.ContainsKey('*:Verbose') | Should -Be $true
            
            InModuleScope Environment {
                Invoke-Teardown
            }
            
            $Global:PSDefaultParameterValues.ContainsKey('*:Verbose') | Should -Be $false
        }

        It 'Should remove Debug from PSDefaultParameterValues' {
            $Global:PSDefaultParameterValues.ContainsKey('*:Debug') | Should -Be $true
            
            InModuleScope Environment {
                Invoke-Teardown
            }
            
            $Global:PSDefaultParameterValues.ContainsKey('*:Debug') | Should -Be $false
        }

        It 'Should remove Module Verbose from PSDefaultParameterValues' {
            $Global:PSDefaultParameterValues.ContainsKey('*-Module:Verbose') | Should -Be $true
            
            InModuleScope Environment {
                Invoke-Teardown
            }
            
            $Global:PSDefaultParameterValues.ContainsKey('*-Module:Verbose') | Should -Be $false
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
            # Remove some keys manually first
            $Global:PSDefaultParameterValues.Remove('*:ErrorAction')
            $Global:PSDefaultParameterValues.Remove('*:Verbose')
            
            InModuleScope Environment {
                { Invoke-Teardown } | Should -Not -Throw
            }
        }
    }

    Context 'Integration with Invoke-Setup' {
        It 'Should clean up all values set by Invoke-Setup' {
            # First set up
            InModuleScope Environment {
                Invoke-Setup
            }
            
            # Verify setup worked
            $Global:PSDefaultParameterValues.ContainsKey('*:ErrorAction') | Should -Be $true
            $Global:PSDefaultParameterValues.ContainsKey('*:WarningAction') | Should -Be $true
            $Global:PSDefaultParameterValues.ContainsKey('*:InformationAction') | Should -Be $true
            
            # Then tear down
            InModuleScope Environment {
                Invoke-Teardown
            }
            
            # Verify teardown worked
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
            # Add some unrelated keys
            $Global:PSDefaultParameterValues['Get-Process:Name'] = 'powershell'
            $Global:PSDefaultParameterValues['Test-Custom:Param'] = 'value'
            
            InModuleScope Environment {
                Invoke-Teardown
            }
            
            # Verify environment-specific keys are removed
            $Global:PSDefaultParameterValues.ContainsKey('*:ErrorAction') | Should -Be $false
            $Global:PSDefaultParameterValues.ContainsKey('*:WarningAction') | Should -Be $false
            
            # Verify other keys are preserved
            $Global:PSDefaultParameterValues.ContainsKey('Get-Process:Name') | Should -Be $true
            $Global:PSDefaultParameterValues.ContainsKey('Test-Custom:Param') | Should -Be $true
            
            # Clean up test keys
            $Global:PSDefaultParameterValues.Remove('Get-Process:Name')
            $Global:PSDefaultParameterValues.Remove('Test-Custom:Param')
        }
    }
}