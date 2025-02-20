BeforeDiscovery { Import-Module -Name "$PSScriptRoot/../../../src/common/Event.psm1" }
AfterAll { Remove-Module Event }

class TestEvent {
    [String]$Name
    TestEvent([String]$Name) { $this.Name = $Name }
}

Describe 'Unregister-EventSubscription Tests' {
    BeforeAll {
        [Type]$Script:EventType = [TestEvent];
        [ScriptBlock]$Script:Callback = { };
    }

    It 'Should remove a subscription from the event' {
        $Id = Register-EventSubscription -EventType $EventType -Callback $Callback;
        Unregister-EventSubscription -EventType $EventType -Id $Id;
        $Script:Events[$EventType].Subscriptions.Count | Should -Be 0
    }
}
