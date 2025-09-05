BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/Analyser.psm1" }

Describe 'Analyser Module Tests' {
    Context 'SuppressAnalyserAttribute Functionality' {
        It 'Should create SuppressAnalyserAttribute with all properties' {
            $Attribute = [Compiler.Analyser.SuppressAnalyserAttribute]::new('TestCheck', 'TestData')
            $Attribute.Justification = 'This is a test justification'

            $Attribute | Should -Not -BeNullOrEmpty
            $Attribute.CheckType | Should -Be 'TestCheck'
            $Attribute.Data | Should -Be 'TestData'
            $Attribute.Justification | Should -Be 'This is a test justification'
        }

        It 'Should support various data types for Data parameter' {
            $StringAttr = [Compiler.Analyser.SuppressAnalyserAttribute]::new('StringCheck', 'StringData')
            $StringAttr.Data | Should -Be 'StringData'

            $NumberAttr = [Compiler.Analyser.SuppressAnalyserAttribute]::new('NumberCheck', 42)
            $NumberAttr.Data | Should -Be 42

            $NullAttr = [Compiler.Analyser.SuppressAnalyserAttribute]::new('NullCheck', $null)
            $NullAttr.Data | Should -Be $null
        }
    }
}
