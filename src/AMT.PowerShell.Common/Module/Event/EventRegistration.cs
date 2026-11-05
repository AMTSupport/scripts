// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Module.Event;

public sealed class EventRegistration {
    // Ascending by Priority (Low=0 first, High=2 last) then by Id; mirrors PS SubscriptionComparer.
    private sealed class SubscriptionComparer : IComparer<Subscription> {
        internal static readonly SubscriptionComparer Instance = new();

        public int Compare(Subscription? x, Subscription? y) {
            if (ReferenceEquals(x, y)) return 0;
            if (x is null) return -1;
            if (y is null) return 1;
            var pc = ((int)x.Priority).CompareTo((int)y.Priority);
            return pc != 0 ? pc : x.Id.CompareTo(y.Id);
        }
    }

    private readonly SortedSet<Subscription> _subscriptions = new(SubscriptionComparer.Instance);
    private readonly object _lock = new();

    public Type EventType { get; }

    public EventRegistration(Type eventType) {
        EventType = eventType;
    }

    // Returns a point-in-time snapshot in dispatch order; safe to read without holding the lock.
    public IReadOnlyList<Subscription> Subscriptions {
        get { lock (_lock) return _subscriptions.ToList(); }
    }

    public Guid Subscribe(ScriptBlock callback, Priority priority = Priority.Normal) {
        var sub = new Subscription(callback, priority);
        lock (_lock) _subscriptions.Add(sub);
        return sub.Id;
    }

    public bool Unsubscribe(Guid id) {
        lock (_lock) {
            var sub = _subscriptions.FirstOrDefault(s => s.Id == id);
            if (sub is null) return false;
            return _subscriptions.Remove(sub);
        }
    }

    public void Dispatch(object instance) {
        Subscription[] snapshot;
        lock (_lock) snapshot = _subscriptions.ToArray();
        foreach (var sub in snapshot) {
            sub.Callback.Invoke(instance);
        }
    }

    public void Clear() {
        lock (_lock) _subscriptions.Clear();
    }
}
