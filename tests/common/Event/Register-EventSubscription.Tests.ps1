BeforeDiscovery { Import-Module -Name "$PSScriptRoot/../../../src/common/Event.psm1" }
AfterAll { Remove-Module Event -ErrorAction SilentlyContinue }

Describe 'Register-EventSubscription Tests' {
    It 'Should throw an error if the event type isn''t registered' {
        [Type]$EventType = [Object];
        {
            Register-EventSubscription -EventType:$EventType -Callback { };
        } | Should -Throw -ExpectedMessage 'Event type System.Object has not been registered';
    }

    Context 'With EventType Registered' {
        BeforeAll {
            class TestEvent {
                [String]$Name
                TestEvent([String]$Name) { $this.Name = $Name }
            }

            [Type]$Script:EventType = [TestEvent];
            Register-Event -EventType $EventType;
        }
        AfterEach { InModuleScope Event {
            $Script:Events = @{};
        }}

        It 'Should add a subscription to the event' {
            Register-EventSubscription -EventType $EventType -Callback { };
            (Get-CustomEvent -EventType $EventType).Subscriptions.Count | Should -BeExactly 1;
        }

        It 'Should return a unique identifier for the subscription' {
            [Int]$Instances = 100;
            [Guid[]]$Ids = @();
            for ($i = 0; $i -lt $Instances; $i++) {
                $Ids += (Register-EventSubscription -EventType $EventType -Callback { });
            }

            ($Ids | Sort-Object -Unique).Count | Should -BeExactly $Instances;
        }
    }
}
