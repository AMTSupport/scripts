BeforeDiscovery {
    $Script:ModuleName = & $PSScriptRoot/Base.ps1;
}


Describe 'Flags.psm1 Tests' {
    AfterEach { $Flag.Remove(); }

    Context 'Base Flag Class' {
        BeforeAll { $Script:Flag = Get-Flag 'TestFlag'; }
        Context 'Set' {
            It 'Should create the flag if it does not exist' {
                $Flag.Exists() | Should -Be $false;
                $Flag.Set($null);
                $Flag.Exists() | Should -Be $true;
            }

            It 'Should overwrite the data if it exists' {
                $OldData = 'Test data';
                $NewData = 'New test data';

                $Flag.Set($OldData);
                $Flag.Set($NewData);
                $Flag.GetData() | Should -BeExactly $NewData;

                $Flag.Set($null);
                $Flag.GetData() | Should -Be $null;
            }
        }

        Context 'Exists' {
            It 'Should return $false when the flag does not exist' {
                $Flag.Exists() | Should -Be $false;
            }

            It 'Should return $true when the flag exists' {
                $Flag.Set($null);
                $Flag.Exists() | Should -Be $true;
            }
        }

        Context 'Remove' {
            It 'Should remove the flag if it exists' {
                $Flag.Set($null);
                $Flag.Exists() | Should -Be $true;
                $Flag.Remove();
                $Flag.Exists() | Should -Be $false;
            }

            It 'Should not throw an error if the flag does not exist' {
                $Flag.Exists() | Should -Be $false;
                $Flag.Remove();
                $Flag.Exists() | Should -Be $false;
            }
        }

        Context 'Data' {
            BeforeEach { $Flag.Set($null); }

            It 'Should return $null when the flag has no data' {
                $Flag.GetData() | Should -Be $null;
            }

            It 'Should return the data when the flag has data' {
                $Data = 'Test data';
                $Flag.Set($Data);
                $Flag.GetData() | Should -BeExactly $Data;
            }
        }
    }

    # TODO
    Context 'Reboot' {
        BeforeAll { $Script:Flag = Get-RebootFlag; }
    }

    # TODO
    Context 'Running' {
        BeforeAll { $Script:Flag = Get-RunningFlag; }
    }
}
