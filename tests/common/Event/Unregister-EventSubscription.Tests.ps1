BeforeDiscovery { Import-Module -Name "$PSScriptRoot/../../../src/common/Event.psm1" }
AfterAll { Remove-Module Event }

Describe 'Unregister-EventSubscription Tests' {
    BeforeAll {
        class TestEvent {
            [String]$Name
            TestEvent([String]$Name) { $this.Name = $Name }
        }

        [Type]$Script:EventType = [TestEvent];
        Register-Event -EventType $EventType;
    }

    It 'Should remove a subscription from the event' {
        $Id = Register-EventSubscription -EventType $EventType -Callback { };
        Unregister-EventSubscription -EventType $EventType -Id $Id;
        InModuleScope Event -Parameters @{ EventType = $EventType } {
            $Script:Events[$EventType].Subscriptions.Count | Should -Be 0
        }
    }

    It 'Should not throw an error when unregistering a non-existent subscription' {
        { Unregister-EventSubscription -EventType $EventType -Id ([Guid]::NewGuid()); } | Should -Not -Throw
    }

    It 'Should properly handle multiple unregister calls' {
        $Id1 = Register-EventSubscription -EventType $EventType -Callback { };
        $Id2 = Register-EventSubscription -EventType $EventType -Callback { };

        Unregister-EventSubscription -EventType $EventType -Id $Id1;
        (Get-CustomEvent -EventType $EventType).Subscriptions.Count | Should -Be 1

        Unregister-EventSubscription -EventType $EventType -Id $Id2;
        (Get-CustomEvent -EventType $EventType).Subscriptions.Count | Should -Be 0
    }

    It 'Should not throw an error when registering a subscription after unregistering' {
        $Id = Register-EventSubscription -EventType $EventType -Callback { };
        Unregister-EventSubscription -EventType $EventType -Id $Id;
        { Register-EventSubscription -EventType $EventType -Callback { } } | Should -Not -Throw
    }
}
