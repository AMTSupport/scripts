// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Diagnostics;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Scope;

public sealed class ScopeFrame {
    internal ScopeFrame(InvocationInfo invocation) {
        this.Invocation = invocation;
        this.Stopwatch = Stopwatch.StartNew();
    }

    public InvocationInfo Invocation { get; }

    public Stopwatch Stopwatch { get; }
}
