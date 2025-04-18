BeforeDiscovery { Import-Module $PSScriptRoot/../../../src/common/Assert.psm1 -ErrorAction Stop }

Describe 'Assert-NotNull Tests' {
    It 'Should throw an error if the object is null' {
        { Assert-NotNull -Object $null } | Should -Throw
    }

    It 'Should not throw an error if the object is not null' {
        { Assert-NotNull -Object 'foo'; } | Should -Not -Throw
    }
}
