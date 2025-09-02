BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/ModuleUtils.psm1" }

Describe 'Add-ModuleCallback Tests' {
    Context 'Basic Functionality' {
        It 'Should add a callback to module OnRemove' {
            $TestModule = New-Module -Name 'TempCallbackModule' -ScriptBlock {
                Import-Module "$($args[0])" -Force
                
                $TestCallback = { Write-Host 'Callback executed' }
                { Add-ModuleCallback -ScriptBlock $TestCallback } | Should -Not -Throw
                
                # Verify the callback was set
                $ExecutionContext.SessionState.Module.OnRemove | Should -Not -BeNullOrEmpty
            } -ArgumentList "$PSScriptRoot/../../../src/common/ModuleUtils.psm1"
            
            Remove-Module -Name 'TempCallbackModule' -Force -ErrorAction SilentlyContinue
        }

        It 'Should execute callback when module is removed' {
            # Create a temporary test file to verify callback execution
            $TestFile = Join-Path ([System.IO.Path]::GetTempPath()) 'callback_test.txt'
            
            $TempModule = New-Module -Name 'TempExecutionModule' -ScriptBlock {
                Import-Module "$($args[0])" -Force
                
                $TestCallback = { 'callback executed' | Out-File -FilePath $args[1] }
                Add-ModuleCallback -ScriptBlock $TestCallback.GetNewClosure()
            } -ArgumentList "$PSScriptRoot/../../../src/common/ModuleUtils.psm1", $TestFile
            
            # Remove the module
            Remove-Module -Name 'TempExecutionModule' -Force
            
            # Verify callback was executed
            Test-Path $TestFile | Should -Be $true
            Get-Content $TestFile | Should -Be 'callback executed'
            
            # Clean up
            Remove-Item $TestFile -Force -ErrorAction SilentlyContinue
        }

        It 'Should handle multiple callbacks' {
            $TestFile1 = Join-Path ([System.IO.Path]::GetTempPath()) 'callback_test1.txt'
            $TestFile2 = Join-Path ([System.IO.Path]::GetTempPath()) 'callback_test2.txt'
            
            $TempModule = New-Module -Name 'MultiCallbackModule' -ScriptBlock {
                Import-Module "$($args[0])" -Force
                
                $TestCallback1 = { 'callback 1 executed' | Out-File -FilePath $args[1] }
                $TestCallback2 = { 'callback 2 executed' | Out-File -FilePath $args[2] }
                
                Add-ModuleCallback -ScriptBlock $TestCallback1.GetNewClosure()
                Add-ModuleCallback -ScriptBlock $TestCallback2.GetNewClosure()
            } -ArgumentList "$PSScriptRoot/../../../src/common/ModuleUtils.psm1", $TestFile1, $TestFile2
            
            # Remove the module
            Remove-Module -Name 'MultiCallbackModule' -Force
            
            # Verify both callbacks were executed
            Test-Path $TestFile1 | Should -Be $true
            Test-Path $TestFile2 | Should -Be $true
            Get-Content $TestFile1 | Should -Be 'callback 1 executed'
            Get-Content $TestFile2 | Should -Be 'callback 2 executed'
            
            # Clean up
            Remove-Item $TestFile1, $TestFile2 -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Error Handling' {
        It 'Should throw when not called from within a module' {
            $TestCallback = { Write-Host 'test' }
            
            { Add-ModuleCallback -ScriptBlock $TestCallback -Module $null } | Should -Throw
        }

        It 'Should handle null script block' {
            $TestModule = New-Module -Name 'TempNullCallbackModule' -ScriptBlock {
                Import-Module "$($args[0])" -Force
                
                { Add-ModuleCallback -ScriptBlock $null } | Should -Throw
            } -ArgumentList "$PSScriptRoot/../../../src/common/ModuleUtils.psm1"
            
            Remove-Module -Name 'TempNullCallbackModule' -Force -ErrorAction SilentlyContinue
        }

        It 'Should handle empty script block' {
            $TestModule = New-Module -Name 'TempEmptyCallbackModule' -ScriptBlock {
                Import-Module "$($args[0])" -Force
                
                $EmptyCallback = {}
                { Add-ModuleCallback -ScriptBlock $EmptyCallback } | Should -Not -Throw
                
                $ExecutionContext.SessionState.Module.OnRemove | Should -Not -BeNullOrEmpty
            } -ArgumentList "$PSScriptRoot/../../../src/common/ModuleUtils.psm1"
            
            Remove-Module -Name 'TempEmptyCallbackModule' -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Callback Chaining' {
        It 'Should chain callbacks when multiple are added' {
            $TestFile = Join-Path ([System.IO.Path]::GetTempPath()) 'chain_test.txt'
            
            $TempModule = New-Module -Name 'ChainCallbackModule' -ScriptBlock {
                Import-Module "$($args[0])" -Force
                
                $FirstCallback = { '1' | Out-File -FilePath $args[1] -NoNewline }
                $SecondCallback = { 
                    if (Test-Path $args[1]) {
                        $content = Get-Content $args[1] -Raw
                        ($content + '2') | Out-File -FilePath $args[1] -NoNewline
                    } else {
                        '2' | Out-File -FilePath $args[1] -NoNewline
                    }
                }
                
                Add-ModuleCallback -ScriptBlock $FirstCallback.GetNewClosure()
                Add-ModuleCallback -ScriptBlock $SecondCallback.GetNewClosure()
                
                # Verify that the OnRemove property contains both callbacks
                $ExecutionContext.SessionState.Module.OnRemove | Should -Not -BeNullOrEmpty
            } -ArgumentList "$PSScriptRoot/../../../src/common/ModuleUtils.psm1", $TestFile
            
            # Remove module and verify both callbacks executed
            Remove-Module -Name 'ChainCallbackModule' -Force
            
            Test-Path $TestFile | Should -Be $true
            $Content = Get-Content $TestFile -Raw
            $Content | Should -Be '12'
            
            # Clean up
            Remove-Item $TestFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Integration with Export-Types' {
        It 'Should work with Export-Types callback registration' {
            $TestFile = Join-Path ([System.IO.Path]::GetTempPath()) 'integration_test.txt'
            
            $TempModule = New-Module -Name 'IntegrationCallbackModule' -ScriptBlock {
                Import-Module "$($args[0])" -Force
                
                # Add a manual callback
                $ManualCallback = { 'manual callback' | Out-File -FilePath $args[1] }
                Add-ModuleCallback -ScriptBlock $ManualCallback.GetNewClosure()
                
                # Export types (which also adds a callback)
                Export-Types -Types @([System.Version])
                
                # Verify both callbacks are registered
                $ExecutionContext.SessionState.Module.OnRemove | Should -Not -BeNullOrEmpty
            } -ArgumentList "$PSScriptRoot/../../../src/common/ModuleUtils.psm1", $TestFile
            
            # Remove module and verify manual callback executed
            Remove-Module -Name 'IntegrationCallbackModule' -Force
            
            Test-Path $TestFile | Should -Be $true
            Get-Content $TestFile | Should -Be 'manual callback'
            
            # Clean up
            Remove-Item $TestFile -Force -ErrorAction SilentlyContinue
        }
    }
}