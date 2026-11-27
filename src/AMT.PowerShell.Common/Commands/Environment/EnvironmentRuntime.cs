// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.EnvironmentCmdlets;

// Host and session interactions that are non-deterministic outside an
// interactive Windows host. Tests substitute these seams instead of touching
// the real window title, disclaimer output, or strict-mode application.
internal static class EnvironmentRuntime {
    internal const string DisclaimerText =
        "Disclaimer: This script is provided as is, without warranty of any kind, " +
        "express or implied, including but not limited to the warranties of " +
        "merchantability, fitness for a particular purpose, and non-infringement. " +
        "In no event shall the author or copyright holders be liable for any claim, " +
        "damages, or other liability, whether in an action of contract, tort, or " +
        "otherwise, arising from, out of, or in connection with the script or the " +
        "use or other dealings in the script.";

    internal static Func<PSCmdlet, string?>? WindowTitleOverride { get; set; }

    internal static Action<string>? DisclaimerOverride { get; set; }

    internal static Action<PSCmdlet>? SetStrictModeOverride { get; set; }

    // Mirrors ($WindowTitle | Split-Path -Leaf). Empty titles yield null, which
    // Test-IsNableRunner treats as false.
    internal static string? GetWindowTitleLeaf(PSCmdlet cmdlet) {
        var title = WindowTitleOverride is not null
            ? WindowTitleOverride(cmdlet)
            : ReadWindowTitle(cmdlet);

        if (string.IsNullOrEmpty(title)) {
            return null;
        }

        return SplitPathLeaf(title!);
    }

    internal static void ShowDisclaimer(PSCmdlet cmdlet) {
        if (DisclaimerOverride is not null) {
            DisclaimerOverride(DisclaimerText);
            return;
        }

        cmdlet.WriteInformation(DisclaimerText, Array.Empty<string>());
    }

    internal static void ApplyStrictMode(PSCmdlet cmdlet) {
        if (SetStrictModeOverride is not null) {
            SetStrictModeOverride(cmdlet);
            return;
        }

        // Mirrors Set-StrictMode -Version 3 from the legacy entrypoint. Run it
        // dot-sourced into the current scope so Main's execution scope inherits it.
        cmdlet.InvokeCommand.InvokeScript(
            cmdlet.SessionState,
            ScriptBlock.Create("Set-StrictMode -Version 3"));
    }

    internal static void SetLastExitCode(PSCmdlet cmdlet, int code) =>
        cmdlet.SessionState.PSVariable.Set("LASTEXITCODE", code);

    internal static void SetRestarting(PSCmdlet cmdlet, bool value) =>
        EnvironmentStore.SetRestarting(EnvironmentStore.RequireRunspace(), value);

    private static string? ReadWindowTitle(PSCmdlet cmdlet) {
        try {
            return cmdlet.Host?.UI?.RawUI?.WindowTitle;
        } catch {
            return null;
        }
    }

    private static string SplitPathLeaf(string path) {
        var trimmed = path.TrimEnd('/', '\\');
        var slash = Math.Max(trimmed.LastIndexOf('/'), trimmed.LastIndexOf('\\'));
        return slash < 0 ? trimmed : trimmed.Substring(slash + 1);
    }
}
