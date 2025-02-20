BeforeDiscovery {
    . $PSScriptRoot/../../../src/common/Event.psm1;
}

Describe 'Register-EventSubscription Tests' {
    AfterEach {
        $Script:Events[$EventType].Subscriptions.Clear();
    }

    It 'Should add a subscription to the event' {
        Register-EventSubscription -EventType:$Script:EventType -Callback:$Script:Callback;
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
