BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/ModuleUtils.psm1" }
Describe 'Add-ModuleCallback Tests' {
    BeforeAll {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', $null)]
        $ModulePath = "$PSScriptRoot/../../../src/common/ModuleUtils.psm1"
    }

    Context 'Basic Functionality' {
        It 'Should execute callback when module is removed' {
            $TestFile = 'TestDrive:\callback_test.txt'

            $TempModuleFolder = ('TestDrive:\TempExecutionModule_' + [Guid]::NewGuid().ToString())
            New-Item -Path $TempModuleFolder -ItemType Directory -Force | Out-Null
            $TempModulePath = Join-Path $TempModuleFolder 'TempExecutionModule.psm1'
            $moduleContent = @"
Import-Module "${ModulePath}" -Force

`$TestCallback = { 'callback executed' | Out-File -FilePath "${TestFile}" }
Add-ModuleCallback -ScriptBlock `$TestCallback.GetNewClosure()
"@
            Set-Content -Path $TempModulePath -Value $moduleContent -Encoding UTF8
            Import-Module -Name $TempModulePath -PassThru | Remove-Module | Out-Null

            Get-Content -Path $TestFile | Should -Be 'callback executed'
        }

        It 'Should handle multiple callbacks' {
            $TestFile1 = 'TestDrive:\callback_test1.txt'
            $TestFile2 = 'TestDrive:\callback_test2.txt'

            $TempModuleFolder = ('TestDrive:\MultiCallbackModule_' + [Guid]::NewGuid().ToString())
            New-Item -Path $TempModuleFolder -ItemType Directory -Force | Out-Null
            $TempModulePath = Join-Path $TempModuleFolder 'MultiCallbackModule.psm1'
            $moduleContent = @"
Import-Module "${ModulePath}" -Force

`$TestCallback1 = { 'callback 1 executed' | Out-File -FilePath "${TestFile1}" }
`$TestCallback2 = { 'callback 2 executed' | Out-File -FilePath "${TestFile2}" }

Add-ModuleCallback -ScriptBlock `$TestCallback1.GetNewClosure()
Add-ModuleCallback -ScriptBlock `$TestCallback2.GetNewClosure()
"@
            Set-Content -Path $TempModulePath -Value $moduleContent -Encoding UTF8
            Import-Module -Name $TempModulePath -PassThru | Remove-Module | Out-Null

            Get-Content -Path $TestFile1 | Should -Be 'callback 1 executed'
            Get-Content -Path $TestFile2 | Should -Be 'callback 2 executed'
        }
    }

    Context 'Error Handling' {
        It 'Should throw when not called from within a module' {
            $TestCallback = { Write-Output 'test' }
            { Add-ModuleCallback -ScriptBlock $TestCallback } | Should -Throw
        }
    }
}
