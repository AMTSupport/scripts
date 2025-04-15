BeforeDiscovery { Import-Module -Name "$PSScriptRoot/../../../src/common/Input.psm1" }

Describe 'Validate Input Tests' {
    It 'Should export the validations variable for use in other tests' {
        $Validations | Should -BeOfType 'Hashtable';
    }

    It 'email validation should return true for <Email>' {
        $Email -match $Validations.Email;
    } -ForEach @(
        { Email = 'test@testing.com' },
        { Email = 'test@testing.com.au' },
        { Email = 'test@mail.testing.com.au' },
        { Email = 'test.user@testing.com' }
    )
}
