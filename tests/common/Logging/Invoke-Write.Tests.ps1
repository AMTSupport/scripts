BeforeDiscovery { Import-Module -Name "$PSScriptRoot/../../../src/common/Logging.psm1" }
AfterAll { Remove-Module Logging }

Describe 'Invoke-Write Tests' {
    It 'Should not write anything if $ShouldWrite is $false' {
        @{
            PSPrefix    = '🌟'
            PSMessage   = 'Test message'
            PSColour    = 'Green'
            ShouldWrite = $false
        } | Invoke-Write -InformationVariable Output;

        $Output | Select-Object -First 1 | Should -Be $null;
    }

    It 'Should write the message if $ShouldWrite is $true' {
        $Params = @{
            PSPrefix    = '🌟'
            PSMessage   = 'Test message'
            PSColour    = 'Green'
            ShouldWrite = $true
        };

        $Params | Invoke-Write -InformationVariable Output;
        $Output | Select-Object -First 1 | Get-Stripped | Should -Be (Get-ShouldBeString $Params.PSMessage);
    }

    It 'Should replace newline characters in the message' {
        $Params = @{
            PSPrefix    = '🌟'
            PSMessage   = "Test message`nSecond line"
            PSColour    = 'Green'
            ShouldWrite = $true
        };

        $Params | Invoke-Write -InformationVariable Output;
        $Output | Select-Object -First 1  | Get-Stripped | Should -Be (Get-ShouldBeString $Params.PSMessage);
    }
}
