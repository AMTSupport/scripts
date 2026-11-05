// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation.Runspaces;
using System.Runtime.CompilerServices;

namespace AMT.PowerShell.Common.Commands.EnvironmentCmdlets;

// Per-runspace restart state for Invoke-RunMain.
// Mirrors $Script:ScriptRestarting from the legacy Environment.psm1.
internal static class EnvironmentStore {
    private sealed class EnvironmentState {
        internal bool Restarting;
    }

    private static readonly ConditionalWeakTable<Runspace, EnvironmentState> States = new();

    internal static Runspace RequireRunspace() =>
        Runspace.DefaultRunspace ?? throw new InvalidOperationException("No active runspace.");

    private static EnvironmentState State(Runspace runspace) =>
        States.GetValue(runspace, _ => new EnvironmentState());

    internal static bool IsRestarting(Runspace runspace) =>
        State(runspace).Restarting;

    internal static void SetRestarting(Runspace runspace, bool value) =>
        State(runspace).Restarting = value;

    internal static void Reset(Runspace runspace) =>
        State(runspace).Restarting = false;
}
