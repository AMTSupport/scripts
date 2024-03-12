BeforeDiscovery {
    $Script:ModuleName = & $PSScriptRoot/Base.ps1;
}

BeforeAll {
    [Void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms');

    function Send-Input([String]$String) {
        return Start-Job -ScriptBlock {
            Start-Sleep -Seconds 1;

            [System.Windows.Forms.SendKeys]::SendWait($using:String);
            [System.Windows.Forms.SendKeys]::SendWait('{ENTER}');
        };
    }
}

Describe 'Input tests' {
    Context 'Validations' {
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

    Context 'Get-UserInput' {
        # It 'Should return the user input' {

        #     Send-Input -String 'Test';
        #     $UserInput = Get-UserInput -Title 'Test' -Question 'Question';

        #     $UserInput | Should -BeOfType 'String';
        #     $UserInput | Should -Be 'Test';
        # }
    }
}
