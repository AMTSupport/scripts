BeforeDiscovery { Import-Module -Name "$PSScriptRoot/../../../src/common/Event.psm1" }
AfterAll { Remove-Module Event -ErrorAction SilentlyContinue }

Describe 'Submit-Event Tests' {
    BeforeAll {
        class TestEvent {
            [String]$Name
            TestEvent([String]$Name) { $this.Name = $Name }
        }

        [Type]$Script:EventType = [TestEvent];
        [ScriptBlock]$Script:Callback = { param($EventInstance) $Global:EventName = $EventInstance.Name; };

        Register-Event -EventType:$Script:EventType;
    }

    It 'Should dispatch the event to all subscribers' {
        Register-EventSubscription -EventType $EventType -Callback $Callback;
        Submit-Event -EventInstance ([TestEvent]::new('Test'));
        $Global:EventName | Should -Be 'Test';
    }
}
