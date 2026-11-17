// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Module.Event;

public sealed class Subscription {
    public Guid Id { get; } = Guid.NewGuid();

    public Priority Priority { get; }

    public ScriptBlock Callback { get; }

    public Subscription(ScriptBlock callback, Priority priority = Priority.Normal) {
        Priority = priority;
        Callback = callback;
    }
}
