BeforeDiscovery { Import-Module $PSScriptRoot/../../../src/common/Assert.psm1 }

Describe 'Assert-Equal Tests' {
    It 'Should throw an error if the object does not equal the expected value' {
        { Assert-Equal -Object 'foo' -Expected 'bar' } | Should -Throw;
    }

    It 'Should not throw an error if the object equals the expected value' {
        Assert-Equal -Object 'foo' -Expected 'foo';
    }

    Context 'Error Message Formatting' {
    }
}
