// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Runtime.CompilerServices;
using System.Threading;

namespace AMT.PowerShell.Common.Commands.Exit;

// Per-runspace registry of exit handlers and deterministic exit codes.
// Mirrors $Script:ExitHandlers/$Script:ExitCodes from the legacy Exit.psm1.
internal static class ExitStore {
    private sealed class ExitState {
        internal readonly ConcurrentDictionary<string, ExitHandlerRegistration> Handlers = new();
        internal readonly object CodeLock = new();
        internal readonly Dictionary<string, int> CodesByDescription = new(StringComparer.OrdinalIgnoreCase);
        internal readonly Dictionary<int, string> DescriptionsByCode = new();
        internal int HandlersRun;
    }

    private static readonly ConditionalWeakTable<Runspace, ExitState> States = new();

    internal static Runspace RequireRunspace() =>
        Runspace.DefaultRunspace ?? throw new InvalidOperationException("No active runspace.");

    private static ExitState State(Runspace runspace) =>
        States.GetValue(runspace, _ => new ExitState());

    internal static void RegisterHandler(Runspace runspace, string name, ScriptBlock script, bool onlyFailure) =>
        State(runspace).Handlers[name] = new ExitHandlerRegistration(name, script, onlyFailure);

    internal static bool Contains(Runspace runspace, string name) =>
        State(runspace).Handlers.ContainsKey(name);

    internal static IReadOnlyList<ExitHandlerRegistration> SnapshotHandlers(Runspace runspace) =>
        State(runspace).Handlers.Values.ToArray();

    internal static bool MarkHandlersRun(Runspace runspace) =>
        Interlocked.Exchange(ref State(runspace).HandlersRun, 1) == 0;

    internal static bool AreHandlersRun(Runspace runspace) =>
        Volatile.Read(ref State(runspace).HandlersRun) != 0;

    // Assigns 1001 + current-count. Reuses the existing code when the same
    // description (case-insensitive) has already been registered.
    internal static int RegisterExitCode(Runspace runspace, string description) {
        var state = State(runspace);
        lock (state.CodeLock) {
            if (state.CodesByDescription.TryGetValue(description, out var existing)) {
                return existing;
            }

            var code = state.DescriptionsByCode.Count + 1001;
            state.CodesByDescription[description] = code;
            state.DescriptionsByCode[code] = description;
            return code;
        }
    }

    internal static string? GetDescription(Runspace runspace, int code) {
        var state = State(runspace);
        lock (state.CodeLock) {
            return state.DescriptionsByCode.TryGetValue(code, out var description) ? description : null;
        }
    }

    internal static void Reset(Runspace runspace) {
        var state = State(runspace);
        state.Handlers.Clear();
        lock (state.CodeLock) {
            state.CodesByDescription.Clear();
            state.DescriptionsByCode.Clear();
        }

        Interlocked.Exchange(ref state.HandlersRun, 0);
    }
}
