// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Linq;
using System.Management.Automation;
using System.Reflection;

namespace AMT.PowerShell.Common.Commands.ModuleUtils;

// Resolves the module of the script that invoked a cmdlet, matching the legacy
// Get-PSCallStack default-module semantics (caller module, not cmdlet module).
internal static class CallerModuleResolver {
    private static readonly PropertyInfo? ContextProperty =
        FindProperty(typeof(PSCmdlet), "Context");

    private static readonly PropertyInfo? DebuggerProperty =
        FindProperty(
            typeof(PSObject).Assembly.GetType("System.Management.Automation.ExecutionContext"),
            "Debugger");

    internal static PSModuleInfo? Resolve(PSCmdlet cmdlet) {
        if (ContextProperty is null || DebuggerProperty is null) {
            return null;
        }

        try {
            var context = ContextProperty.GetValue(cmdlet);
            if (context is null) {
                return null;
            }

            var debugger = DebuggerProperty.GetValue(context) as Debugger;
            if (debugger is null) {
                return null;
            }

            // The binary cmdlet is not part of the script call stack, so the
            // first frame is the nearest script scope (the caller).
            return debugger.GetCallStack()
                .Select(frame => GetModule(frame.InvocationInfo?.MyCommand))
                .FirstOrDefault(module => module is not null);
        } catch {
            return null;
        }
    }

    private static PSModuleInfo? GetModule(CommandInfo? command) {
        if (command is null) {
            return null;
        }

        // Match legacy ScriptBlock.Module semantics for script commands.
        ScriptBlock? scriptBlock = command switch {
            FunctionInfo function => function.ScriptBlock,
            ExternalScriptInfo external => external.ScriptBlock,
            _ => null
        };

        return scriptBlock?.Module ?? command.Module;
    }

    private static PropertyInfo? FindProperty(Type? type, string name) {
        for (var current = type; current is not null; current = current.BaseType) {
            var property = current.GetProperty(
                name,
                BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            if (property is not null) {
                return property;
            }
        }

        return null;
    }
}
