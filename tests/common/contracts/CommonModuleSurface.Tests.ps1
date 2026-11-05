Describe 'Common module surface contracts' {
    BeforeAll {
        . "$PSScriptRoot/../../../utils/common/Export-CommonContract.ps1"
    }

    It 'matches frozen exported function surface' {
        $live = Get-CommonModuleSurface -CommonRoot "$PSScriptRoot/../../../src/common"
        $expected = Get-Content "$PSScriptRoot/TestData/common-exports.json" -Raw | ConvertFrom-Json -AsHashtable

        $liveJson = $live.Exports | ConvertTo-Json -Depth 10
        $expectedJson = $expected.Exports | ConvertTo-Json -Depth 10

        $liveJson | Should -BeExactly $expectedJson
    }
}
