// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation.Runspaces;

namespace AMT.PowerShell.Common.Commands.Exit;

internal static class ExitHandlerRunner {
    // Runs each registered handler exactly once per runspace.
    // Failure-only handlers are skipped when isFailure is false.
    internal static void Invoke(Runspace runspace, bool isFailure, Action<string> debug, Action<string> warn) {
        if (ExitStore.AreHandlersRun(runspace)) {
            debug("Exit handlers already run, skipping...");
            return;
        }

        foreach (var handler in ExitStore.SnapshotHandlers(runspace)) {
            if (handler.OnlyFailure && !isFailure) {
                continue;
            }

            debug($"Invoking exit handler '{handler.Name}'...");
            try {
                handler.Script.Invoke();
            } catch (Exception exception) {
                warn($"Failed to invoke exit handler '{handler.Name}': {exception.Message}");
            }
        }

        ExitStore.MarkHandlersRun(runspace);
    }
}
