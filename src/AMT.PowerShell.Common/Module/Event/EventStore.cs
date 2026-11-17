// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;

namespace AMT.PowerShell.Common.Module.Event;

// Thread-safe process-wide registry of event types.
internal static class EventStore {
    private static readonly ConcurrentDictionary<Type, EventRegistration> Events = new();

    // Overwrites any existing registration, dropping prior subscriptions (matches PS legacy).
    internal static void Register(Type type) => Events[type] = new EventRegistration(type);

    internal static EventRegistration? Get(Type type) =>
        Events.TryGetValue(type, out var reg) ? reg : null;

    internal static IDictionary<Type, EventRegistration> GetAll() =>
        new Dictionary<Type, EventRegistration>(Events);

    internal static bool IsRegistered(Type type) => Events.ContainsKey(type);

    // Clears all registrations; intended for test isolation only.
    internal static void Reset() => Events.Clear();
}
