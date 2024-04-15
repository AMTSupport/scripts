BeforeDiscovery {
    $Script:ModuleName = & $PSScriptRoot/Base.ps1;
}

class TestEvent {
    [String]$Name
    TestEvent([String]$Name) { $this.Name = $Name }
}

BeforeAll {
    [Type]$Script:EventType = [TestEvent];
    [ScriptBlock]$Script:Callback = { param($EventInstance) $Global:foo = 'bar'; };

    Register-Event -EventType:$Script:EventType;
}

Describe 'Event System' {
    AfterEach {
        $Script:Events[$EventType].Subscriptions.Clear();
    }

    Context 'Register-EventSubscription Function' {
        It 'Should add a subscription to the event' {
            Register-EventSubscription -EventType:$Script:EventType -Callback:$Script:Callback;

            Invoke-Info "$((Get-Event -EventType:$EventType).Subscriptions)";

            (Get-Event -EventType:$EventType).Subscriptions.Count | Should -BeExactly 1;
        }

        It 'Should return the a unique identifier for the subscription' {
            [Int]$Private:Instances = 100;
            [Guid[]]$Private:Ids = @();
            for ($i = 0; $i -lt $Private:Instances; $i++) {
                $Private:Ids += Register-EventSubscription -EventType:$Script:EventType -Callback:$Script:Callback;
            }

            ($Private:Ids | Sort-Object -Unique).Count | Should -BeExactly $Private:Instances;
        }
    }

    Context 'Submit-Event Function' {
        BeforeAll {
            $Script:Events = [System.Collections.Generic.Dictionary[Type, Event]]::new()
        }

        It 'Should dispatch the event to all subscribers' {
            Register-EventSubscription -EventType $EventType -Callback $Callback;
            Submit-Event -EventInstance ([TestEvent]::new('Test')) | Should -Be 'Test'
        }
    }

    Context 'Unregister-EventSubscription Function' {
        BeforeAll {
            $Script:Events = [System.Collections.Generic.Dictionary[Type, Event]]::new()
        }

        It 'Should remove a subscription from the event' {
            $Id = Register-EventSubscription -EventType $EventType -Callback $Callback;
            Unregister-EventSubscription -EventType $EventType -Id $Id;
            $Script:Events[$EventType].Subscriptions.Count | Should -Be 0
        }
    }
}
