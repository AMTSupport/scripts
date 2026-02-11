BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/Environment.psm1" }

Describe 'Invoke-Setup Tests' {
    BeforeAll {
        # Save original values
        $Script:OriginalErrorActionPreference = $Global:ErrorActionPreference
        $Script:OriginalPSDefaultParameterValues = $Global:PSDefaultParameterValues.Clone()
    }

    AfterAll {
        # Restore original values
        $Global:ErrorActionPreference = $Script:OriginalErrorActionPreference
        $Global:PSDefaultParameterValues = $Script:OriginalPSDefaultParameterValues
    }

    AfterEach {
        # Clean up after each test
        $Global:PSDefaultParameterValues.Remove('*:ErrorAction')
        $Global:PSDefaultParameterValues.Remove('*:WarningAction')
        $Global:PSDefaultParameterValues.Remove('*:InformationAction')
        $Global:PSDefaultParameterValues.Remove('*:Verbose')
        $Global:PSDefaultParameterValues.Remove('*:Debug')
        $Global:PSDefaultParameterValues.Remove('*-Module:Verbose')
    }

    Context 'Parameter Value Configuration' {
        It 'Should set global PSDefaultParameterValues for ErrorAction' {
            InModuleScope Environment {
                Invoke-Setup
            }
            
            $Global:PSDefaultParameterValues['*:ErrorAction'] | Should -Not -BeNullOrEmpty
        }

        It 'Should set global PSDefaultParameterValues for WarningAction' {
            InModuleScope Environment {
                Invoke-Setup
            }
            
            $Global:PSDefaultParameterValues['*:WarningAction'] | Should -Not -BeNullOrEmpty
        }

        It 'Should set global PSDefaultParameterValues for InformationAction' {
            InModuleScope Environment {
                Invoke-Setup
            }
            
            $Global:PSDefaultParameterValues['*:InformationAction'] | Should -Not -BeNullOrEmpty
        }

        It 'Should configure Verbose parameter based on preferences' {
            InModuleScope Environment {
                $VerbosePreference = 'Continue'
                $DebugPreference = 'Continue'
                Invoke-Setup
                
                $Global:PSDefaultParameterValues['*:Verbose'] | Should -Be $true
            }
        }

        It 'Should configure Debug parameter based on preferences' {
            InModuleScope Environment {
                $DebugPreference = 'Continue'
                Invoke-Setup
                
                $Global:PSDefaultParameterValues['*:Debug'] | Should -Be $true
            }
        }

        It 'Should set module-specific verbose preference based on debug preference' {
            InModuleScope Environment {
                $DebugPreference = 'Continue'
                Invoke-Setup
                
                $Global:PSDefaultParameterValues['*-Module:Verbose'] | Should -Be $true
            }
        }
    }

    Context 'ErrorActionPreference Configuration' {
        It 'Should set global ErrorActionPreference to Stop' {
            InModuleScope Environment {
                Invoke-Setup
            }
            
            $Global:ErrorActionPreference | Should -Be 'Stop'
        }

        It 'Should preserve current preference values in PSDefaultParameterValues' {
            $TestErrorActionPreference = 'Continue'
            $TestWarningPreference = 'Continue'
            $TestInformationPreference = 'Continue'
            
            $Global:ErrorActionPreference = $TestErrorActionPreference
            $Global:WarningPreference = $TestWarningPreference
            $Global:InformationPreference = $TestInformationPreference
            
            InModuleScope Environment {
                Invoke-Setup
            }
            
            $Global:PSDefaultParameterValues['*:ErrorAction'] | Should -Be $TestErrorActionPreference
            $Global:PSDefaultParameterValues['*:WarningAction'] | Should -Be $TestWarningPreference
            $Global:PSDefaultParameterValues['*:InformationAction'] | Should -Be $TestInformationPreference
        }
    }

    Context 'Preference Logic' {
        It 'Should set Verbose to false when VerbosePreference is SilentlyContinue' {
            InModuleScope Environment {
                $VerbosePreference = 'SilentlyContinue'
                $DebugPreference = 'SilentlyContinue'
                Invoke-Setup
            }
            
            $Global:PSDefaultParameterValues['*:Verbose'] | Should -Be $false
        }

        It 'Should set Debug to false when DebugPreference is SilentlyContinue' {
            InModuleScope Environment {
                $DebugPreference = 'SilentlyContinue'
                Invoke-Setup
            }
            
            $Global:PSDefaultParameterValues['*:Debug'] | Should -Be $false
        }

        It 'Should set Debug to false when DebugPreference is Ignore' {
            InModuleScope Environment {
                $DebugPreference = 'Ignore'
                Invoke-Setup
            }
            
            $Global:PSDefaultParameterValues['*:Debug'] | Should -Be $false
        }
    }
}