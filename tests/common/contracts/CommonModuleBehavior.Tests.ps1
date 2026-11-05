Describe 'Common module dependency contracts' {
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

    It 'matches frozen using module dependency surface' {
        $live = Get-CommonModuleSurface -CommonRoot "$PSScriptRoot/../../../src/common"
        $expected = Get-Content "$PSScriptRoot/TestData/common-using-map.json" -Raw | ConvertFrom-Json @Script:JsonParseSwitch

        $liveJson = $live.UsingMap | ConvertTo-Json -Depth 10
        $expectedJson = $expected.UsingMap | ConvertTo-Json -Depth 10

        $liveJson | Should -BeExactly $expectedJson
    }
}
