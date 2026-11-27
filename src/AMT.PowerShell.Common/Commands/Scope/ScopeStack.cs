// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.Concurrent;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Runtime.CompilerServices;

namespace AMT.PowerShell.Common.Commands.Scope;

// Per-runspace stack of Enter-Scope/Exit-Scope frames.
// Mirrors $Script:InvocationStack from the legacy Scope.psm1.
internal static class ScopeStack {
    private sealed class ScopeState {
        internal readonly ConcurrentStack<ScopeFrame> Frames = new();
    }

    private static readonly ConditionalWeakTable<Runspace, ScopeState> States = new();

    internal static Runspace RequireRunspace() =>
        Runspace.DefaultRunspace ?? throw new InvalidOperationException("No active runspace.");

    private static ScopeState State(Runspace runspace) =>
        States.GetValue(runspace, _ => new ScopeState());

    internal static int Count(Runspace runspace) => State(runspace).Frames.Count;

    internal static void Push(Runspace runspace, InvocationInfo invocation) =>
        State(runspace).Frames.Push(new ScopeFrame(invocation));

    internal static bool TryPop(Runspace runspace, out ScopeFrame? frame) =>
        State(runspace).Frames.TryPop(out frame);

    internal static bool TryPeek(Runspace runspace, out ScopeFrame? frame) =>
        State(runspace).Frames.TryPeek(out frame);

    // Builds the chain from previous frames sorted descending by name (legacy
    // Sort-Object -Descending), followed by the current top frame name.
    internal static string FormatName(Runspace runspace, bool isExit) {
        var frames = State(runspace).Frames.ToArray();
        if (frames.Length == 0) {
            throw new InvalidOperationException("The scope stack is empty.");
        }

        var current = ResolveName(frames[0]);
        var previous = frames.Skip(1)
            .Select(ResolveName)
            .OrderByDescending(name => name, StringComparer.OrdinalIgnoreCase)
            .ToList();

        if (previous.Count == 0) {
            return current;
        }

        var separator = isExit ? " < " : " > ";
        return string.Join(" > ", previous) + separator + current;
    }

    private static string ResolveName(ScopeFrame frame) =>
        frame.Invocation.MyCommand?.Name ?? frame.Invocation.InvocationName;
}
