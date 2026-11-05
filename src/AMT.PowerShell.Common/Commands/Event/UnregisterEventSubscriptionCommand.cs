// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;
using AMT.PowerShell.Common.Module.Event;

namespace AMT.PowerShell.Common.Commands.Event;

/// <summary>Remove a subscription from a registered event, returning <see langword="true"/> if it was found and removed.</summary>
/// <remarks>
/// Returns <see langword="false"/> when the event type is not registered, or no subscription
/// with the given GUID exists. Idempotent — calling with an already-removed <see cref="Id"/> returns
/// <see langword="false"/> without error.
/// </remarks>
/// <example>
/// <code>Unregister-EventSubscription -EventType ([MyEvent]) -Id $subscriptionId</code>
/// Removes the subscription identified by $subscriptionId from the MyEvent registration.
/// </example>
[Cmdlet(VerbsLifecycle.Unregister, "EventSubscription")]
[OutputType(typeof(bool))]
public sealed class UnregisterEventSubscriptionCommand : Cmdlet {
    /// <summary>CLR type whose event registration contains the subscription to remove.</summary>
    [Parameter(Mandatory = true)]
    public Type EventType { get; set; } = null!;

    /// <summary>GUID returned by <c>Register-EventSubscription</c> when the subscription was created.</summary>
    [Parameter(Mandatory = true)]
    public Guid Id { get; set; }

    protected override void ProcessRecord() {
        var reg = EventStore.Get(EventType);
        if (reg is null) {
            WriteObject(false);
            return;
        }

        WriteObject(reg.Unsubscribe(Id));
    }
}
