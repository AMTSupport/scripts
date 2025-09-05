BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/ModuleUtils.psm1" }

Describe 'Export-Types Tests' {
    Context 'Basic Functionality' {
        BeforeEach {
            $ModulePath = "$PSScriptRoot/../../../src/common/ModuleUtils.psm1"
            $TypeAcceleratorsClass = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
            $namespace = 'TempExportTypes_' + ([Guid]::NewGuid().ToString().Replace('-', ''))
            $TestModulePath = "TestDrive:\$namespace.psm1"
        }

        It 'Should export types to TypeAccelerators' {
            $CSharpClass = "namespace $namespace { public class TempType1 {} public class TempType2 {} }"
            Set-Content -Path $TestModulePath -Value @"
Import-Module "${ModulePath}" -Force
Add-Type -TypeDefinition "$CSharpClass" -Language CSharp
Export-Types -Types @([${namespace}.TempType1], [${namespace}.TempType2])
"@
            Import-Module $TestModulePath

            $ExistingTypeAccelerators = $TypeAcceleratorsClass::Get
            $ExistingTypeAccelerators.Keys -contains "$namespace.TempType1" | Should -Be $true
            $ExistingTypeAccelerators.Keys -contains "$namespace.TempType2" | Should -Be $true
        }
    }

    Context 'Clobber Parameter' {
        It 'Should allow clobbering with Clobber switch' {
            $csharp = "namespace $namespace { public class TempDateTime {} }"
            Set-Content -Path $TestModulePath -Value @"
Import-Module "${ModulePath}" -Force

Add-Type -TypeDefinition "$csharp" -Language CSharp

`$TestTypes = @([${namespace}.TempDateTime])
Export-Types -Types `$TestTypes
Export-Types -Types `$TestTypes -Clobber
"@
            { Import-Module -Name $TestModulePath } | Should -Not -Throw
        }
    }

    Context 'Module Callback Integration' {
        It 'Should register removal callback' {
            $csharp = "namespace $namespace { public class TempGuid {} }"
            Set-Content -Path $TestModulePath -Value @"
Import-Module "${ModulePath}" -Force

Add-Type -TypeDefinition "$csharp" -Language CSharp
Export-Types -Types @([${namespace}.TempGuid])
"@
            Import-Module -Name $TestModulePath

            $ExistingTypeAccelerators = $TypeAcceleratorsClass::Get
            $ExistingTypeAccelerators.Keys -contains "$namespace.TempGuid" | Should -Be $false
        }
    }
}
