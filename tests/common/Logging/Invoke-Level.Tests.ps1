BeforeDiscovery { Import-Module -Name "$PSScriptRoot/../../../src/common/Logging.psm1" }
AfterAll { Remove-Module Logging }

BeforeAll {
    function Get-ShouldBeString([String]$String) {
        $FixedString = $String -replace "`n", "`n+ ";

        InModuleScope Logging {
            if (Test-SupportsUnicode) {
                # There is an extra space at the end of the string
                $FixedString = " $FixedString"
            }
        }

        return $FixedString;
    }

    function Get-Stripped([Parameter(ValueFromPipeline)][String]$String) {
        # Replace all non-ASCII characters with a nothing string
        # Replace all ANSI escape sequences with a nothing string
        $String -replace '[^\u0000-\u007F]', '' -replace '\x1B\[[0-9;]*m', '';
    }

    $Params = @{
        Message   = 'Test message'
    };
}

Describe 'Invoke-Level Tests' {
    Context 'Invoke-Error Tests' {
        It 'Should write when $ErrorActionPreference is Continue' {
            $Global:ErrorActionPreference = 'Continue';
            $Params | Invoke-Error -InformationVariable Output;
            $Output | Select-Object -First 1 | Get-Stripped | Should -Be (Get-ShouldBeString $Params.Message);
        }

        It 'Should not write when $ErrorActionPreference is SilentlyContinue or Ignore' {
            $Global:ErrorActionPreference = 'SilentlyContinue';
            $Params | Invoke-Error -InformationVariable Output;
            $Output | Select-Object -First 1 | Should -Be $null;

            $Global:ErrorActionPreference = 'Ignore';
            $Params | Invoke-Error -InformationVariable Output;
            $Output | Select-Object -First 1 | Should -Be $null;
        }
    }

    Context 'Invoke-Warn Tests' {
        It 'Should write when $WarningPreference is Continue' {
            $Global:WarningPreference = 'Continue';
            $Params | Invoke-Warn -InformationVariable Output;
            $Output | Select-Object -First 1 | Get-Stripped | Should -Be (Get-ShouldBeString $Params.Message);
        }

        It 'Should not write when $WarningPreference is SilentlyContinue or Ignore' {
            $Global:WarningPreference = 'SilentlyContinue';
            $Params | Invoke-Warn -InformationVariable Output;
            $Output | Select-Object -First 1 | Should -Be $null;

            $Global:WarningPreference = 'Ignore';
            $Params | Invoke-Warn -InformationVariable Output;
            $Output | Select-Object -First 1 | Should -Be $null;
        }
    }

    Context 'Invoke-Info Tests' {
        It 'Should write when $InformationPreference is Continue' {
            $Global:InformationPreference = 'Continue';
            $Params | Invoke-Info -InformationVariable Output;
            $Output | Select-Object -First 1 | Get-Stripped | Should -Be (Get-ShouldBeString $Params.Message);
        }

        It 'Should not write when $InformationPreference is Ignore' {
            $Global:InformationPreference = 'Ignore';
            $Params | Invoke-Info -InformationVariable Output;
            $Output | Select-Object -First 1 | Should -Be $null;
        }
    }

    Context 'Invoke-Verbose Tests' {
        It 'Should write when $VerbosePreference is Continue' {
            $Global:VerbosePreference = 'Continue';
            $Params | Invoke-Verbose -InformationVariable Output;
            $Output | Select-Object -First 1 | Get-Stripped | Should -Be (Get-ShouldBeString $Params.Message);
        }

        It 'Should not write when $VerbosePreference is SilentlyContinue or Ignore' {
            $Global:VerbosePreference = 'SilentlyContinue';
            $Params | Invoke-Verbose -InformationVariable Output;
            $Output | Select-Object -First 1 | Should -Be $null;

            $Global:VerbosePreference = 'Ignore';
            $Params | Invoke-Verbose -InformationVariable Output;
            $Output | Select-Object -First 1 | Should -Be $null;
        }
    }

    Context 'Invoke-Debug Tests' {
        It 'Should write when $DebugPreference is Continue' {
            $Global:DebugPreference = 'Continue';
            $Params | Invoke-Debug -InformationVariable Output;
            $Output | Select-Object -First 1 | Get-Stripped | Should -Be (Get-ShouldBeString $Params.Message);
        }

        It 'Should not write when $DebugPreference is SilentlyContinue or Ignore' {
            $Global:DebugPreference = 'SilentlyContinue';
            $Params | Invoke-Debug -InformationVariable Output;
            $Output | Select-Object -First 1 | Should -Be $null;

            $Global:DebugPreference = 'Ignore';
            $Params | Invoke-Debug -InformationVariable Output;
            $Output | Select-Object -First 1 | Should -Be $null;
        }
    }
}
