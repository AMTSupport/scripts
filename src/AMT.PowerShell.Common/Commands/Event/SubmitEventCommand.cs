// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Management.Automation;
using AMT.PowerShell.Common.Module.Event;

namespace AMT.PowerShell.Common.Commands.Event;

/// <summary>Dispatch an event instance to all subscribers registered for its runtime type.</summary>
/// <remarks>
/// The runtime type of <see cref="EventInstance"/> determines which <c>EventRegistration</c> is looked up.
/// <see cref="System.Management.Automation.PSObject"/> wrappers are unwrapped before dispatch.
/// Silently no-ops when no registration exists for the type.
/// </remarks>
/// <example>
/// <code>Submit-Event -EventInstance ([MyEvent]::new('payload'))</code>
/// Dispatches a MyEvent instance to all currently registered subscribers.
/// </example>
[Cmdlet(VerbsLifecycle.Submit, "Event")]
public sealed class SubmitEventCommand : Cmdlet {
    /// <summary>Event object to dispatch; its runtime type must match a type registered via <c>Register-Event</c>.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNull]
    public object EventInstance { get; set; } = null!;

    protected override void ProcessRecord() {
        // PowerShell may wrap the object in PSObject; unwrap before dispatch.
        var actual = EventInstance is PSObject ps ? ps.BaseObject : EventInstance;
        var reg = EventStore.Get(actual.GetType());
        reg?.Dispatch(actual);
    }
}
