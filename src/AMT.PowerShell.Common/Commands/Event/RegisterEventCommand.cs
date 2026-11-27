// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;
using AMT.PowerShell.Common.Module.Event;

namespace AMT.PowerShell.Common.Commands.Event;

/// <summary>Register a CLR type as a dispatchable event in the event store.</summary>
/// <remarks>
/// Creates an empty <see cref="EventRegistration"/> for the given type.
/// Must be called before <c>Register-EventSubscription</c> or <c>Submit-Event</c> can be used
/// with that type.
/// </remarks>
/// <example>
/// <code>Register-Event -EventType ([MyEvent])</code>
/// Registers MyEvent so that subscriptions and dispatches can target it.
/// </example>
[Cmdlet(VerbsLifecycle.Register, "Event")]
public sealed class RegisterEventCommand : Cmdlet {
    /// <summary>CLR type to register as a dispatchable event.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public Type EventType { get; set; } = null!;

    protected override void ProcessRecord() => EventStore.Register(EventType);
}
