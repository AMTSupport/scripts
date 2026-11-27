// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;
using AMT.PowerShell.Common.Module.Event;

namespace AMT.PowerShell.Common.Commands.Event;

/// <summary>Subscribe a script block to a registered event type, returning the subscription GUID.</summary>
/// <remarks>
/// The event type must have been registered with <c>Register-Event</c> before subscribing.
/// Callbacks are invoked in <see cref="Priority"/> order (High before Normal before Low);
/// within the same priority, dispatch order is deterministic by subscription GUID.
/// </remarks>
/// <example>
/// <code>$id = Register-EventSubscription -EventType ([MyEvent]) -Callback { param($e) Write-Host $e }</code>
/// Subscribes to MyEvent and stores the GUID for later removal.
/// </example>
[Cmdlet(VerbsLifecycle.Register, "EventSubscription")]
[OutputType(typeof(Guid))]
public sealed class RegisterEventSubscriptionCommand : Cmdlet {
    /// <summary>CLR type whose event this callback subscribes to; must already be registered via <c>Register-Event</c>.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public Type EventType { get; set; } = null!;

    /// <summary>Script block invoked when an event of <see cref="EventType"/> is dispatched; receives the event instance as its first argument.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNull]
    public ScriptBlock Callback { get; set; } = null!;

    /// <summary>Dispatch priority relative to other subscribers for the same event type; defaults to <see cref="Priority.Normal"/>.</summary>
    [Parameter]
    public Priority Priority { get; set; } = Priority.Normal;

    protected override void ProcessRecord() {
        var reg = EventStore.Get(EventType);
        if (reg is null) {
            ThrowTerminatingError(new ErrorRecord(
                new InvalidOperationException($"Event type {EventType} has not been registered"),
                "EventTypeNotRegistered",
                ErrorCategory.InvalidArgument,
                EventType));
            return;
        }

        WriteObject(reg.Subscribe(Callback, Priority));
    }
}
