Describe 'Common module dependency contracts' {
    BeforeAll {
        . "$PSScriptRoot/../../../utils/common/Export-CommonContract.ps1"
    }

    It 'matches frozen using module dependency surface' {
        $live = Get-CommonModuleSurface -CommonRoot "$PSScriptRoot/../../../src/common"
        $expected = Get-Content "$PSScriptRoot/TestData/common-using-map.json" -Raw | ConvertFrom-Json -AsHashtable

        $liveJson = $live.UsingMap | ConvertTo-Json -Depth 10
        $expectedJson = $expected.UsingMap | ConvertTo-Json -Depth 10

        $liveJson | Should -BeExactly $expectedJson
    }
}
