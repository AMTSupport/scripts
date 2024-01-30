BeforeDiscovery {
    Import-Module $PSScriptRoot/../../src/common/00-Logging.psm1
}

BeforeAll {
    function Get-ShouldBeString([String]$String) {
        $String -replace "`n", "`n+ ";
    }

    function Get-Stripped([Parameter(ValueFromPipeline)][String]$String) {
        # Replace all non-ASCII characters with a nothing string
        # Replace all ANSI escape sequences with a nothing string
        $String -replace '[^\u0000-\u007F]', '' -replace '\x1B\[[0-9;]*m', ''
    }
}

AfterAll {
    Remove-Module 00-Logging
}

Describe '00-Logging.psm1 Tests' {
    Context 'Get-SupportsUnicode' {
        It 'Should return $true' {
            Get-SupportsUnicode | Should -Be $true
        }
    }

    Context 'Invoke-Write' {
        It 'Should not write anything if $ShouldWrite is $false' {
            @{
                PSMessage   = 'Test message'
                PSColour    = 'Green'
                ShouldWrite = $false
            } | Invoke-Write -InformationVariable Output;

            $Output | Select-Object -First 1 | Should -Be $null;
        }

        It 'Should write the message if $ShouldWrite is $true' {
            $Params = @{
                PSMessage   = 'Test message'
                PSColour    = 'Green'
            };

            $Params | Invoke-Write -InformationVariable Output;
            $Output | Select-Object -First 1 | Get-Stripped | Should -Be (Get-ShouldBeString $Params.PSMessage);
        }

        It 'Should replace newline characters in the message' {
            $Params = @{
                PSMessage   = "Test message`nSecond line"
                PSColour    = 'Green'
            };

            $Params | Invoke-Write -InformationVariable Output;
            $Output | Select-Object -First 1  | Get-Stripped | Should -Be (Get-ShouldBeString $Params.PSMessage);
        }
    }
}
