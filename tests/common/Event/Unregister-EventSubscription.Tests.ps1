BeforeDiscovery { Import-Module -Name "$PSScriptRoot/../../../src/common/Event.psm1" }
AfterAll { Remove-Module Event }

Describe 'Unregister-EventSubscription Tests' {
    BeforeAll {
        class TestEvent {
            [String]$Name
            TestEvent([String]$Name) { $this.Name = $Name }
        }

        [Type]$Script:EventType = [TestEvent];
    }

    It 'Should remove a subscription from the event' {
        $Id = Register-EventSubscription -EventType $EventType -Callback { };
        Unregister-EventSubscription -EventType $EventType -Id $Id;
        $Script:Events[$EventType].Subscriptions.Count | Should -Be 0
    }

    It 'Should not throw an error when unregistering a non-existent subscription' {
        { Unregister-EventSubscription -EventType $EventType -Id ([Guid]::NewGuid()) } | Should -Not -Throw
    }

    It 'Should properly handle multiple unregister calls' {
        $Id1 = Register-EventSubscription -EventType $EventType -Callback { };
        $Id2 = Register-EventSubscription -EventType $EventType -Callback { };

        Unregister-EventSubscription -EventType $EventType -Id $Id1;
        $Script:Events[$EventType].Subscriptions.Count | Should -Be 1
        Get-CustomEvent -EventType $EventType | Should -Not -BeNullOrEmpty

        Unregister-EventSubscription -EventType $EventType -Id $Id2;
        $Script:Events[$EventType].Subscriptions.Count | Should -Be 0
        Get-CustomEvent -EventType $EventType | Should -BeNullOrEmpty
    }
}
