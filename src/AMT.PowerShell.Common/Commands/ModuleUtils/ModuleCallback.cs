// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.Generic;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.ModuleUtils;

internal static class ModuleCallback {
    private const string PreviousName = "__amt_module_callback_previous";
    private const string NextName = "__amt_module_callback_next";

    // Appends callback to module.OnRemove, preserving the existing chain.
    // Mirrors the legacy GetNewClosure composition from ModuleUtils.psm1.
    internal static void Add(PSModuleInfo module, ScriptBlock callback, SessionState sessionState) {
        var previous = module.OnRemove;
        if (previous is null) {
            module.OnRemove = callback;
            return;
        }

        module.OnRemove = CreateClosure(
            sessionState,
            $"& ${PreviousName}; & ${NextName};",
            new Dictionary<string, object?> {
                [PreviousName] = previous,
                [NextName] = callback
            });
    }

    // Builds a ScriptBlock whose free variables are captured from the current
    // session state, so the script survives past the cmdlet invocation scope.
    internal static ScriptBlock CreateClosure(
        SessionState sessionState,
        string script,
        IDictionary<string, object?> variables) {
        foreach (var pair in variables) {
            sessionState.PSVariable.Set(pair.Key, pair.Value);
        }

        try {
            return ScriptBlock.Create(script).GetNewClosure();
        } finally {
            foreach (var key in variables.Keys) {
                sessionState.PSVariable.Remove(key);
            }
        }
    }
}
