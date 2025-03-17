[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'Required for testing')]
param()

BeforeDiscovery { Import-Module -Name "$PSScriptRoot/../../../src/common/Utils.psm1" }
AfterAll { Remove-Module Utils -ErrorAction SilentlyContinue }

Describe 'ConvertTo-InvokableValue tests' {
    It 'Should return "$null" for null input' {
        $Result = ConvertTo-InvokableValue -Value $null
        $Result | Should -Be '$null'

        Invoke-Expression $Result | Should -Be $null
    }

    It 'Should return "$True" for boolean True input' {
        $Value = $True
        $Result = ConvertTo-InvokableValue -Value $Value
        $Result | Should -Be '$True'
        Invoke-Expression $Result | Should -Be $Value
    }

    It 'Should return "$False" for boolean False input' {
        $Value = $False
        $Result = ConvertTo-InvokableValue -Value $Value
        $Result | Should -Be '$False'
        Invoke-Expression $Result | Should -Be $Value
    }

    It 'Should return JSON string for string input' {
        $Value = 'Hello, World!'
        $Result = ConvertTo-InvokableValue -Value $Value;
        $Result | Should -Be '"Hello, World!"'
        Invoke-Expression $Result | Should -Be $Value
    }

    It 'Should return JSON string for integer input' {
        $Value = 123
        $Result = ConvertTo-InvokableValue -Value $Value
        $Result | Should -Be '123'
        Invoke-Expression $Result | Should -Be $Value
    }

    It 'Should return JSON string for array input' {
        $Value = @(1, 2, 3)
        $Result = ConvertTo-InvokableValue -Value $Value
        $Result | Should -Be '@(1, 2, 3)'
        Invoke-Expression $Result | Should -Be $Value
    }

    Context 'Hashtable Conversions' {
        It 'Should return JSON string for hashtable input' {
            $Value = @{ Key = 'Value' }
            $Result = ConvertTo-InvokableValue -Value $Value
            $Result | Should -Be '@{Key = "Value"}'
            $Result = Invoke-Expression $Result
            $Result.Keys | Should -Be $Value.Keys
            $Result.Values | Should -Be $Value.Values
        }

        It 'Should return JSON string for nested hashtable input' {
            $Value = @{ OuterKey = @{ InnerKey = 'InnerValue' } }
            $Result = ConvertTo-InvokableValue -Value $Value
            $Result | Should -Be '@{OuterKey = @{InnerKey = "InnerValue"}}'
            Invoke-Expression $Result | ConvertTo-Json | Should -Be ($Value | ConvertTo-Json)
        }

        It 'Should handle empty hashtable input' {
            $Value = @{}
            $Result = ConvertTo-InvokableValue -Value $Value
            $Result | Should -Be '@{}'
            $Result = Invoke-Expression $Result
            $Result.Keys | Should -BeNullOrEmpty
            $Result.Values | Should -BeNullOrEmpty
        }

        It 'Should return JSON string for hashtable with multiple entries' {
            $Value = @{ Key1 = 'Value1'; Key2 = 'Value2' }
            $Result = ConvertTo-InvokableValue -Value $Value
            $Result | Should -Match -RegularExpression '@{Key(1|2) = "Value(1|2)"; Key(1|2) = "Value(1|2)"}'
            Invoke-Expression $Result | ConvertTo-Json | Should -Be ($Value | ConvertTo-Json)
        }
    }
}
