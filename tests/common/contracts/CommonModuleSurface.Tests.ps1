Describe 'Common module surface contracts' {
    BeforeAll {
        $ConvertFromJsonParams = (Get-Command ConvertFrom-Json).Parameters
        if ($ConvertFromJsonParams.ContainsKey('AsOrderedHashtable')) {
            $Script:JsonParseSwitch = @{ AsOrderedHashtable = $true }
        } else {
            if ($PSVersionTable.PSVersion -lt [Version]'7.3.0') {
                throw 'Common contract tests require PowerShell 7.3+ for deterministic snapshot parsing.'
            }

            $Script:JsonParseSwitch = @{ AsHashtable = $true }
        }

        . "$PSScriptRoot/../../../utils/common/Export-CommonContract.ps1"
    }

    It 'matches frozen exported function surface' {
        $live = Get-CommonModuleSurface -CommonRoot "$PSScriptRoot/../../../src/common"
        $expected = Get-Content "$PSScriptRoot/TestData/common-exports.json" -Raw | ConvertFrom-Json @Script:JsonParseSwitch

        $liveJson = $live.Exports | ConvertTo-Json -Depth 10
        $expectedJson = $expected.Exports | ConvertTo-Json -Depth 10

        $liveJson | Should -BeExactly $expectedJson
    }
}
