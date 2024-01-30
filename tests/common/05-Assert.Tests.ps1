BeforeDiscovery {
    Import-Module $PSScriptRoot/../../src/common/00-Environment.psm1;
    Import-CommonModules;
}

AfterAll {
    Remove-CommonModules;
}

Describe '05-Assert.psm1 Tests' {
    Context 'Assert-NotNull' {
        It 'Should throw an error if the object is null' {
            { Assert-NotNull -Object $null } | Should -Throw
        }

        It 'Should throw an error if the object is empty' {
            { Assert-NotNull -Object '' } | Should -Throw
        }

        It 'Should not throw an error if the object is not null' {
            Assert-NotNull -Object 'foo';
        }
    }

    Context 'Assert-Equals' {
        It 'Should throw an error if the object does not equal the expected value' {
            { Assert-Equals -Object 'foo' -Expected 'bar' } | Should -Throw
        }

        It 'Should not throw an error if the object equals the expected value' {
            Assert-Equals -Object 'foo' -Expected 'foo';
        }
    }
}
