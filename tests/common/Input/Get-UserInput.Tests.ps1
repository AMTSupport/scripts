BeforeDiscovery { Import-Module -Name "$PSScriptRoot/../../../src/common/Input.psm1" }

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

# Describe 'Get-UserInput Tests' {
#     It 'Should return the user input' {
#         Mock -CommandName Read-Host -MockWith { 'test' };

#         $Result = Get-UserInput -Title 'Hello' -Question 'World';
#         $Result | Should -BeExactly 'test';
#     } -Skip
# }
