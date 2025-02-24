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

class ByPriority: System.Collections.Generic.IComparer[Subscription] {
    ByPriority() { }

    [Int] Compare([Subscription]$a, [Subscription]$b) {
        [Int]$OneValue = [Int]$a.Priority;
        [Int]$TwoValue = [Int]$b.Priority;

        if ($OneValue -eq $TwoValue) {
            return 0;
        }

        if ($OneValue -lt $TwoValue) {
            return -1;
        }

        return 1;
    }
}

class EventRegistration {
    [Type]$EventType;
    [System.Collections.Generic.SortedSet[Subscription]]$Subscriptions;

    EventRegistration([Type]$EventType) {
        $this.EventType = $EventType;
    }

    <#
    .SYNOPSIS
        Subscribes to the event returning an ID.
    #>
    [Guid] Subscribe([Subscription]$Subscription) {
        # Lazy initialization
        if ($null -eq $this.Subscriptions) {
            $this.Subscriptions = [System.Collections.Generic.SortedSet[Subscription]]::new([ByPriority]::new());
        }

        $this.Subscriptions.Add($Subscription);
        return $this.Subscriptions.Guid;
    }

    [Boolean] Unsubscribe([Guid]$Guid) {
        if ($null -eq $this.Subscriptions -or $this.Subscriptions.Count -eq 0) {
            return $false;
        }

        # FIXME: Performance issue
        [Int]$Private:Index = $this.Subscriptions.FindIndex({ param($Subscription) $Subscription.Guid -eq $Guid });
        if ($Private:Index -eq -1) {
            return $false;
        }

        $this.Subscriptions.RemoveAt($Private:Index);
        return $true;
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

    [Subscription]$Private:Subscription = [Subscription]::new($EventType, $Priority, $Callback);
    $Script:Events[$EventType].Subscribe($Private:Subscription);

    return $Private:Subscription.Guid;
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
    [ByPriority],
    [EventRegistration]
)

Export-ModuleMember -Function Register-EventSubscription, Submit-Event, Unregister-EventSubscription, Register-Event, Get-CustomEvent;
