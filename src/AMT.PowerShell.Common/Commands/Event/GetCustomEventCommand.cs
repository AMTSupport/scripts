// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;
using AMT.PowerShell.Common.Module.Event;

namespace AMT.PowerShell.Common.Commands.Event;

/// <summary>Retrieve one or all registered custom event registrations from the event store.</summary>
/// <remarks>
/// Without <see cref="EventType"/>, returns the full registration dictionary
/// (a <see cref="System.Collections.Hashtable"/> keyed by <see cref="Type"/>, mirroring the legacy
/// <c>$Script:Events</c> variable) as a single un-enumerated object.
/// With <see cref="EventType"/>, returns the matching <see cref="EventRegistration"/>, or nothing
/// if that type has not been registered.
/// </remarks>
/// <example>
/// <code>Get-CustomEvent -EventType ([MyEvent])</code>
/// Returns the EventRegistration for MyEvent, or nothing if unregistered.
/// </example>
/// <example>
/// <code>Get-CustomEvent</code>
/// Returns the entire event-store dictionary.
/// </example>
[Cmdlet(VerbsCommon.Get, "CustomEvent")]
[OutputType(typeof(EventRegistration))]
public sealed class GetCustomEventCommand : Cmdlet {
    /// <summary>CLR type whose <see cref="EventRegistration"/> is requested; omit to return all registrations.</summary>
    [Parameter(Position = 0)]
    public Type? EventType { get; set; }

    protected override void ProcessRecord() {
        if (EventType is not null) {
            var reg = EventStore.Get(EventType);
            if (reg is not null) WriteObject(reg);
        } else {
            // Legacy shape: returns the full dictionary keyed by Type (mirrors $Script:Events).
            WriteObject(EventStore.GetAll(), enumerateCollection: false);
        }
    }
}
