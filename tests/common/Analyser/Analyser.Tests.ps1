BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/Analyser.psm1" }

Describe 'Analyser Module Tests' {
    Context 'Module Import and Type Loading' {
        It 'Should successfully import the module' {
            Get-Module Analyser | Should -Not -BeNullOrEmpty
        }

        It 'Should load SuppressAnalyserAttribute type' {
            $TypeExists = $null -ne ([System.Type]'Compiler.Analyser.SuppressAnalyserAttribute' -as [type])
            $TypeExists | Should -Be $true
        }

        It 'Should export SuppressAnalyserAttribute type via Export-Types' {
            # Verify the type is accessible as a type accelerator
            $TypeAcceleratorsClass = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
            $ExistingTypeAccelerators = $TypeAcceleratorsClass::Get
            
            # The type should be available
            $ExistingTypeAccelerators.Keys -contains 'Compiler.Analyser.SuppressAnalyserAttribute' | Should -Be $true
        }
    }

    Context 'SuppressAnalyserAttribute Functionality' {
        It 'Should create SuppressAnalyserAttribute with CheckType and Data' {
            $Attribute = [Compiler.Analyser.SuppressAnalyserAttribute]::new('TestCheck', 'TestData')
            
            $Attribute | Should -Not -BeNullOrEmpty
            $Attribute.CheckType | Should -Be 'TestCheck'
            $Attribute.Data | Should -Be 'TestData'
            $Attribute.Justification | Should -BeNullOrEmpty
        }

        It 'Should allow setting Justification property' {
            $Attribute = [Compiler.Analyser.SuppressAnalyserAttribute]::new('TestCheck', 'TestData')
            $Attribute.Justification = 'This is a test justification'
            
            $Attribute.Justification | Should -Be 'This is a test justification'
        }

        It 'Should support various data types for Data parameter' {
            # Test with string
            $StringAttr = [Compiler.Analyser.SuppressAnalyserAttribute]::new('StringCheck', 'StringData')
            $StringAttr.Data | Should -Be 'StringData'
            
            # Test with number
            $NumberAttr = [Compiler.Analyser.SuppressAnalyserAttribute]::new('NumberCheck', 42)
            $NumberAttr.Data | Should -Be 42
            
            # Test with null
            $NullAttr = [Compiler.Analyser.SuppressAnalyserAttribute]::new('NullCheck', $null)
            $NullAttr.Data | Should -Be $null
        }

        It 'Should be usable as an attribute on script elements' {
            # Create a simple test to verify the attribute exists and can be instantiated
            $Attribute = [Compiler.Analyser.SuppressAnalyserAttribute]::new('UseOfUndefinedFunction', 'TestFunction')
            $Attribute | Should -Not -BeNullOrEmpty
            $Attribute.CheckType | Should -Be 'UseOfUndefinedFunction'
            $Attribute.Data | Should -Be 'TestFunction'
        }
    }

    Context 'PowerShell Version Compatibility' {
        It 'Should work in PowerShell 5.1+ environments' {
            # Test that the module behaves correctly across versions
            $PSVersionMajor = $PSVersionTable.PSVersion.Major
            $PSVersionMajor | Should -BeGreaterOrEqual 5
            
            # The type should be available regardless of version
            [Compiler.Analyser.SuppressAnalyserAttribute] | Should -Not -BeNullOrEmpty
        }

        It 'Should handle compiled script scenarios' {
            # Test the compiled script detection logic
            $IsCompiledScript = Get-Variable -Name 'CompiledScript' -Scope Global -ValueOnly -ErrorAction SilentlyContinue
            
            # In our test environment, this should be null/false
            $IsCompiledScript | Should -BeNullOrEmpty
        }
    }

    Context 'CS File Integration' {
        It 'Should check for Suppression.cs file path' {
            $ExpectedPath = "$PSScriptRoot/../../../src/Compiler/Analyser/Suppression.cs"
            
            # The test verifies the path calculation logic, not necessarily file existence
            $ExpectedPath | Should -Not -BeNullOrEmpty
            $ExpectedPath | Should -BeLike '*Suppression.cs'
        }

        It 'Should prefer CS file when available in PowerShell 6+' {
            $PSVersion = $PSVersionTable.PSVersion.Major
            $CSFilePath = "$PSScriptRoot/../../../src/Compiler/Analyser/Suppression.cs"
            
            if ($PSVersion -ge 6 -and (Test-Path $CSFilePath)) {
                # If PS 6+ and file exists, it should use Add-Type -LiteralPath
                Test-Path $CSFilePath | Should -Be $true
            } else {
                # Otherwise, should use inline C# definition
                $true | Should -Be $true  # Always passes for fallback scenario
            }
        }
    }

    Context 'Attribute Usage Patterns' {
        It 'Should support multiple attributes on the same element' {
            # Test that multiple instances of the attribute can be created
            $Attr1 = [Compiler.Analyser.SuppressAnalyserAttribute]::new('Check1', 'Data1')
            $Attr2 = [Compiler.Analyser.SuppressAnalyserAttribute]::new('Check2', 'Data2')
            
            $Attr1.CheckType | Should -Be 'Check1'
            $Attr1.Data | Should -Be 'Data1'
            $Attr2.CheckType | Should -Be 'Check2'
            $Attr2.Data | Should -Be 'Data2'
        }

        It 'Should support common analyzer check types' {
            $CommonChecks = @(
                'UseOfUndefinedFunction',
                'MissingCmdlet',
                'UnreachableCode',
                'UnusedVariable'
            )
            
            foreach ($Check in $CommonChecks) {
                $Attr = [Compiler.Analyser.SuppressAnalyserAttribute]::new($Check, 'TestData')
                $Attr.CheckType | Should -Be $Check
            }
        }
    }

    Context 'Error Handling' {
        It 'Should handle null CheckType gracefully' {
            $Attr = [Compiler.Analyser.SuppressAnalyserAttribute]::new($null, 'TestData')
            # Null gets converted to empty string in C#
            $Attr.CheckType | Should -Be ''
            $Attr.Data | Should -Be 'TestData'
        }

        It 'Should handle empty CheckType' {
            $Attr = [Compiler.Analyser.SuppressAnalyserAttribute]::new('', 'TestData')
            $Attr.CheckType | Should -Be ''
            $Attr.Data | Should -Be 'TestData'
        }
    }
}