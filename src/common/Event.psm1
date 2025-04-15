Using module .\ModuleUtils.psm1
Using module .\Logging.psm1

[HashTable]$Script:Events = @{};

enum Priority {
    Low
    Normal
    High
}

class Subscription {
    [Guid]$Guid;
    [Type]$EventType;
    [Priority]$Priority;
    [ScriptBlock]$Callback;

    Subscription([Type]$EventType, [ScriptBlock]$Callback) {
        [Subscription]::new($EventType, [Priority]::Normal, [ScriptBlock]$Callback);
    }

    Subscription([Type]$EventType, [Priority]$Priority, [ScriptBlock]$Callback) {
        $this.Guid = [Guid]::NewGuid()
        $this.EventType = $EventType
        $this.Priority = $Priority
        $this.Callback = $Callback
    }
}

class SubscriptionComparer: System.Collections.Generic.IComparer[Subscription] {
    SubscriptionComparer() { }

    [Int] Compare([Subscription]$x, [Subscription]$y) {
        if ($x.Priority -eq $y.Priority) {
            return $x.Guid.CompareTo($y.Guid);
        }

        return $x.Priority.CompareTo($y.Priority);
    }
}

class EventRegistration {
    [Type]$EventType;
    [System.Collections.Generic.SortedSet[Subscription]]$Subscriptions;

    EventRegistration([Type]$EventType) {
        $this.EventType = $EventType;
        $this.Subscriptions = [System.Collections.Generic.SortedSet[Subscription]]::new([SubscriptionComparer]::new());
    }

    <#
    .SYNOPSIS
        Subscribes to the event returning an ID.
    #>
    [Guid] Subscribe([Subscription]$Subscription) {
        # Lazy initialization
        if ($null -eq $this.Subscriptions) {
            $this.Subscriptions = [System.Collections.Generic.SortedSet[Subscription]]::new([SubscriptionComparer]::new());
        }

        $null = $this.Subscriptions.Add($Subscription);
        return $Subscription.Guid;
    }

    [Boolean] Unsubscribe([Guid]$Guid) {
        if ($null -eq $this.Subscriptions -or $this.Subscriptions.Count -eq 0) {
            return $false;
        }

        $Subscription = $this.Subscriptions | Where-Object { $_.Guid -eq $Guid };
        if ($null -eq $Subscription) {
            return $false;
        }

        return $this.Subscriptions.Remove($Subscription);
    }

    [Void] Dispatch([Object]$EventInstance) {
        foreach ($Subscription in $this.Subscriptions) {
            $Subscription.Callback.Invoke($EventInstance)
        }
    }

    [Void] Clear() {
        $this.Subscriptions.Clear();
    }
}

function Register-EventSubscription {
    [CmdletBinding()]
    [OutputType([Guid])]
    param(
        [Parameter(Mandatory)]
        [Type]$EventType,

        [Parameter()]
        [Priority]$Priority = [Priority]::Normal,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [ScriptBlock]$Callback
    )

    if ($null -eq $Script:Events[$EventType]) {
        Invoke-Error -Message "Event type $EventType has not been registered" -Throw -ErrorCategory InvalidArgument;
    }

    [Subscription]$Subscription = [Subscription]::new($EventType, $Priority, $Callback);
    return $Script:Events[$EventType].Subscribe($Subscription);
}

function Submit-Event {
    [CmdletBinding()]
    [OutputType([Void])]
    param(
        [Object]$EventInstance
    )

    $Script:Events[$EventInstance.GetType()].Dispatch($EventInstance)
}

function Unregister-EventSubscription {
    [CmdletBinding()]
    [OutputType([Boolean])]
    param(
        [Parameter(Mandatory)]
        [Type]$EventType,

        [Parameter(Mandatory)]
        [Guid]$Id
    )

    if ($null -eq $Script:Events[$EventType]) {
        return $false;
    }

    return $Script:Events[$EventType].Unsubscribe($Id);
}

function Register-Event {
    [CmdletBinding()]
    [OutputType([Void])]
    param(
        [Type]$EventType
    )

    $Script:Events[$EventType] = [EventRegistration]::new($EventType)
}

function Get-CustomEvent {
    [CmdletBinding()]
    [OutputType(ParameterSetName = 'Specific', [EventRegistration])]
    [OutputType(ParameterSetName = 'Default', [Hashtable])]
    param(
        [Parameter(ParameterSetName = 'Specific')]
        [Type]$EventType
    )

    if ($EventType) {
        return $Script:Events[$EventType]
    }

    return $Script:Events
}

Export-Types -Types @(
    [Priority],
    [Subscription],
    [SubscriptionComparer],
    [EventRegistration]
)

Export-ModuleMember -Function Register-EventSubscription, Submit-Event, Unregister-EventSubscription, Register-Event, Get-CustomEvent;
