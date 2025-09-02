BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/ModuleUtils.psm1" }

Describe 'Export-Types Tests' {
    Context 'Basic Functionality' {
        It 'Should export types to TypeAccelerators' {
            # Create a temporary module for testing
            $TestModule = New-Module -Name 'TempExportTypesModule' -ScriptBlock {
                Import-Module "$($args[0])" -Force
                
                # Define test types
                $TestTypes = @([System.String], [System.Int32])
                
                # This should not throw
                Export-Types -Types $TestTypes
                
                # Verify types are accessible
                $TypeAcceleratorsClass = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
                $ExistingTypeAccelerators = $TypeAcceleratorsClass::Get
                
                $ExistingTypeAccelerators.Keys -contains 'System.String' | Should -Be $true
                $ExistingTypeAccelerators.Keys -contains 'System.Int32' | Should -Be $true
            } -ArgumentList "$PSScriptRoot/../../../src/common/ModuleUtils.psm1"
            
            # Clean up
            Remove-Module -Name 'TempExportTypesModule' -Force -ErrorAction SilentlyContinue
        }

        It 'Should handle empty type array' {
            $TestModule = New-Module -Name 'TempEmptyTypesModule' -ScriptBlock {
                Import-Module "$($args[0])" -Force
                
                $EmptyTypes = @()
                { Export-Types -Types $EmptyTypes } | Should -Not -Throw
            } -ArgumentList "$PSScriptRoot/../../../src/common/ModuleUtils.psm1"
            
            Remove-Module -Name 'TempEmptyTypesModule' -Force -ErrorAction SilentlyContinue
        }

        It 'Should handle single type' {
            $TestModule = New-Module -Name 'TempSingleTypeModule' -ScriptBlock {
                Import-Module "$($args[0])" -Force
                
                $SingleType = @([System.Boolean])
                { Export-Types -Types $SingleType } | Should -Not -Throw
                
                $TypeAcceleratorsClass = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
                $ExistingTypeAccelerators = $TypeAcceleratorsClass::Get
                
                $ExistingTypeAccelerators.Keys -contains 'System.Boolean' | Should -Be $true
            } -ArgumentList "$PSScriptRoot/../../../src/common/ModuleUtils.psm1"
            
            Remove-Module -Name 'TempSingleTypeModule' -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Error Handling' {
        It 'Should throw when not called from within a module' {
            # This should throw because we're not in a module context
            { Export-Types -Types @([System.String]) -Module $null } | Should -Throw
        }

        It 'Should handle null types array' {
            $TestModule = New-Module -Name 'TempNullTypesModule' -ScriptBlock {
                Import-Module "$($args[0])" -Force
                
                { Export-Types -Types $null } | Should -Throw
            } -ArgumentList "$PSScriptRoot/../../../src/common/ModuleUtils.psm1"
            
            Remove-Module -Name 'TempNullTypesModule' -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Clobber Parameter' {
        It 'Should allow clobbering with Clobber switch' {
            $TestModule = New-Module -Name 'TempClobberModule' -ScriptBlock {
                Import-Module "$($args[0])" -Force
                
                $TestTypes = @([System.DateTime])
                
                # First export
                Export-Types -Types $TestTypes
                
                # Second export with clobber should not throw
                { Export-Types -Types $TestTypes -Clobber } | Should -Not -Throw
            } -ArgumentList "$PSScriptRoot/../../../src/common/ModuleUtils.psm1"
            
            Remove-Module -Name 'TempClobberModule' -Force -ErrorAction SilentlyContinue
        }

        It 'Should handle re-export from same module without Clobber' {
            $TestModule = New-Module -Name 'TempReExportModule' -ScriptBlock {
                Import-Module "$($args[0])" -Force
                
                $TestTypes = @([System.TimeSpan])
                
                # First export
                Export-Types -Types $TestTypes
                
                # Second export from same module should not throw (allowed behavior)
                { Export-Types -Types $TestTypes } | Should -Not -Throw
            } -ArgumentList "$PSScriptRoot/../../../src/common/ModuleUtils.psm1"
            
            Remove-Module -Name 'TempReExportModule' -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Module Callback Integration' {
        It 'Should register removal callback' {
            $TestModule = New-Module -Name 'TempCallbackIntegrationModule' -ScriptBlock {
                Import-Module "$($args[0])" -Force
                
                $TestTypes = @([System.Guid])
                Export-Types -Types $TestTypes
                
                # Verify the module has an OnRemove callback
                $ExecutionContext.SessionState.Module.OnRemove | Should -Not -BeNullOrEmpty
            } -ArgumentList "$PSScriptRoot/../../../src/common/ModuleUtils.psm1"
            
            Remove-Module -Name 'TempCallbackIntegrationModule' -Force -ErrorAction SilentlyContinue
        }
    }
}