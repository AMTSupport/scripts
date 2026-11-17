// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Net;

namespace AMT.PowerShell.Common.Commands.Input;

internal static class InputOperations {
    internal const string EmailValidationPattern = "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$";

    internal static Func<PSCmdlet, string, string, bool, string?>? ReadInputOverride { get; set; }

    internal static Func<PSCmdlet, string, string, IReadOnlyList<string>, int?, InputSelectionResult>? ReadSelectionOverride { get; set; }

    internal static Func<PSCmdlet, string, object[], bool, bool, object?>? PopupSelectionOverride { get; set; }

    internal static bool ForcePopupFallback { get; set; }

    internal static void EnsureValidationsVariable(PSCmdlet cmdlet) {
        if (cmdlet.SessionState is null) {
            return;
        }

        var existing = cmdlet.SessionState.PSVariable.GetValue("Validations");
        if (existing is Hashtable table && table.ContainsKey("Email")) {
            return;
        }

        cmdlet.SessionState.PSVariable.Set("Validations", BuildValidationsTable());
    }

    internal static void EnsureValidationsVariable(SessionStateProxy? sessionStateProxy) {
        if (sessionStateProxy is null) {
            return;
        }

        var existing = sessionStateProxy.GetVariable("Validations");
        if (existing is Hashtable table && table.ContainsKey("Email")) {
            return;
        }

        sessionStateProxy.SetVariable("Validations", BuildValidationsTable());
    }

    internal static string? ReadInput(PSCmdlet cmdlet, string title, string question, bool asSecureString) {
        if (ReadInputOverride is not null) {
            return ReadInputOverride(cmdlet, title, question, asSecureString);
        }

        try {
            if (!string.IsNullOrWhiteSpace(title)) {
                cmdlet.Host.UI.WriteLine(title);
            }

            if (!string.IsNullOrWhiteSpace(question)) {
                cmdlet.Host.UI.WriteLine(question);
            }

            if (asSecureString) {
                var secure = cmdlet.Host.UI.ReadLineAsSecureString();
                return secure is null
                    ? null
                    : new NetworkCredential(string.Empty, secure).Password;
            }

            return cmdlet.Host.UI.ReadLine();
        } catch (PipelineStoppedException) {
            return null;
        } catch (NotImplementedException) {
            return null;
        }
    }

    internal static InputSelectionResult ReadSelection(
        PSCmdlet cmdlet,
        string title,
        string question,
        IReadOnlyList<string> choices,
        int? defaultChoice) {
        if (ReadSelectionOverride is not null) {
            return ReadSelectionOverride(cmdlet, title, question, choices, defaultChoice);
        }

        try {
            if (!string.IsNullOrWhiteSpace(title)) {
                cmdlet.Host.UI.WriteLine(title);
            }

            if (!string.IsNullOrWhiteSpace(question)) {
                cmdlet.Host.UI.WriteLine(question);
            }

            cmdlet.Host.UI.WriteLine($"Enter one of the following: {string.Join(", ", choices)}");

            if (defaultChoice.HasValue && defaultChoice.Value >= 0 && defaultChoice.Value < choices.Count) {
                cmdlet.Host.UI.Write($">> {choices[defaultChoice.Value]} ");
            } else {
                cmdlet.Host.UI.Write(">> ");
            }

            var input = cmdlet.Host.UI.ReadLine();
            return new InputSelectionResult(false, input);
        } catch (PipelineStoppedException) {
            return InputSelectionResult.Canceled;
        } catch (NotImplementedException) {
            return InputSelectionResult.Canceled;
        }
    }

    internal static object? ReadPopupSelection(
        PSCmdlet cmdlet,
        string title,
        object[] items,
        bool allowNone,
        bool allowMultiple) {
        if (PopupSelectionOverride is not null) {
            return PopupSelectionOverride(cmdlet, title, items, allowNone, allowMultiple);
        }

        if (!ForcePopupFallback) {
            var outGridSelection = TryOutGridViewSelection(title, items, allowMultiple);
            if (HasSelection(outGridSelection, allowMultiple)) {
                return outGridSelection;
            }
        }

        if (allowNone) {
            return null;
        }

        if (items.Length == 0) {
            return null;
        }

        if (allowMultiple) {
            return items.ToArray();
        }

        return items[0];
    }

    internal static bool HasSelection(object? selection, bool allowMultiple) {
        if (selection is null) {
            return false;
        }

        if (!allowMultiple) {
            return true;
        }

        if (selection is Array array) {
            return array.Length > 0;
        }

        return true;
    }

    private static Hashtable BuildValidationsTable() => new(StringComparer.OrdinalIgnoreCase) {
        ["Email"] = EmailValidationPattern,
    };

    private static object? TryOutGridViewSelection(string title, object[] items, bool allowMultiple) {
        try {
            using var powerShell = System.Management.Automation.PowerShell.Create(RunspaceMode.CurrentRunspace);

            var script = allowMultiple
                ? "$args[0] | Out-GridView -Title $args[1] -OutputMode Multiple"
                : "$args[0] | Out-GridView -Title $args[1] -PassThru";

            powerShell.AddScript(script)
                .AddArgument(items)
                .AddArgument(title);

            var results = powerShell.Invoke();
            if (powerShell.HadErrors) {
                return null;
            }

            if (allowMultiple) {
                return results.Select(static item => item.BaseObject).ToArray();
            }

            return results.Count > 0
                ? results[0].BaseObject
                : null;
        } catch {
            return null;
        }
    }
}

internal readonly struct InputSelectionResult {
    internal InputSelectionResult(bool isCanceled, string? value) {
        this.IsCanceled = isCanceled;
        this.Value = value;
    }

    internal bool IsCanceled { get; }

    internal string? Value { get; }

    internal static InputSelectionResult Canceled { get; } = new(isCanceled: true, value: null);
}
