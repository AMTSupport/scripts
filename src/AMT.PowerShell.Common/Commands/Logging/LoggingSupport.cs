// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections;
using System.Globalization;
using System.Management.Automation;
using System.Threading;

namespace AMT.PowerShell.Common.Commands.Logging;

internal static class LoggingRuntime {
    internal const string Reset = "\u001b[0m";

    private static readonly string[] ForegroundColorMap = {
        "\u001b[30m", // Black
        "\u001b[34m", // DarkBlue
        "\u001b[32m", // DarkGreen
        "\u001b[36m", // DarkCyan
        "\u001b[31m", // DarkRed
        "\u001b[35m", // DarkMagenta
        "\u001b[33m", // DarkYellow
        "\u001b[37m", // Gray
        "\u001b[90m", // DarkGray
        "\u001b[94m", // Blue
        "\u001b[92m", // Green
        "\u001b[96m", // Cyan
        "\u001b[91m", // Red
        "\u001b[95m", // Magenta
        "\u001b[93m", // Yellow
        "\u001b[97m", // White
    };

    internal static Func<bool>? SupportsUnicodeOverride { get; set; }

    internal static Func<bool>? SupportsColourOverride { get; set; }

    internal static Func<bool>? ConsoleKeyAvailableOverride { get; set; }

    internal static Action<int>? SleepOverride { get; set; }

    internal static bool SupportsUnicode =>
        SupportsUnicodeOverride?.Invoke() ??
        !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("WT_SESSION"));

    internal static bool SupportsColour =>
        SupportsColourOverride?.Invoke() ?? true;

    internal static bool ConsoleKeyAvailable =>
        ConsoleKeyAvailableOverride?.Invoke() ?? TryReadConsoleKeyAvailable();

    internal static void Sleep(int milliseconds) {
        if (SleepOverride is not null) {
            SleepOverride(milliseconds);
            return;
        }

        Thread.Sleep(milliseconds);
    }

    internal static string MapForegroundColor(string colour) {
        if (string.IsNullOrWhiteSpace(colour)) {
            return string.Empty;
        }

        if (Enum.TryParse<ConsoleColor>(colour, ignoreCase: true, out var consoleColor)) {
            return MapForegroundColor(consoleColor);
        }

        return string.Empty;
    }

    internal static string MapForegroundColor(ConsoleColor colour) {
        var index = (int)colour;
        return index < 0 || index >= ForegroundColorMap.Length
            ? string.Empty
            : ForegroundColorMap[index];
    }

    private static bool TryReadConsoleKeyAvailable() {
        try {
            return Console.KeyAvailable;
        } catch (InvalidOperationException) {
            return false;
        }
    }
}

internal static class LoggingHelper {
    internal static string FormatMessage(string message, string? prefix, string colour, int multiLineIndent) {
        var newLineTab = prefix is not null && LoggingRuntime.SupportsUnicode
            ? new string(' ', prefix.Length + multiLineIndent)
            : new string(' ', multiLineIndent);

        string formatted;
        if (message.Contains('\n')) {
            formatted = message.Replace("\n", "\n" + newLineTab + "+ ");
        } else {
            formatted = message;
        }

        if (LoggingRuntime.SupportsColour && !string.IsNullOrEmpty(colour)) {
            var colourSequence = LoggingRuntime.MapForegroundColor(colour);
            formatted = formatted.Replace(LoggingRuntime.Reset, LoggingRuntime.Reset + colourSequence);
            formatted = colourSequence + formatted + LoggingRuntime.Reset;
        }

        if (prefix is not null && LoggingRuntime.SupportsUnicode) {
            formatted = prefix + " " + formatted;
        }

        return formatted;
    }

    internal static void Emit(
        PSCmdlet cmdlet,
        string message,
        string? prefix,
        string colour,
        int multiLineIndent,
        bool passThru,
        string? informationTag) {
        var formatted = FormatMessage(message, prefix, colour, multiLineIndent);

        if (passThru) {
            cmdlet.WriteObject(formatted);
            return;
        }

        var record = new InformationRecord(formatted, null);
        if (!string.IsNullOrWhiteSpace(informationTag)) {
            record.Tags.Add(informationTag);
        }

        // Legacy Invoke-Write forces display by setting InformationPreference to Continue
        // before emitting, so the record is shown regardless of the ambient preference.
        var previous = cmdlet.SessionState.PSVariable.GetValue("InformationPreference");
        cmdlet.SessionState.PSVariable.Set("InformationPreference", ActionPreference.Continue);
        try {
            cmdlet.WriteInformation(record);
        } finally {
            cmdlet.SessionState.PSVariable.Set("InformationPreference", previous);
        }
    }

    internal static ActionPreference ReadPreference(PSCmdlet cmdlet, string name) =>
        CoercePreference(cmdlet.SessionState.PSVariable.GetValue(name));

    internal static ActionPreference CoercePreference(object? value) {
        if (value is ActionPreference preference) {
            return preference;
        }

        if (value is string text && Enum.TryParse(text, ignoreCase: true, out preference)) {
            return preference;
        }

        return ActionPreference.SilentlyContinue;
    }

    internal static bool ShouldWriteLevel(ActionPreference preference, bool infoStyle) {
        if (infoStyle) {
            return preference != ActionPreference.Ignore;
        }

        return preference != ActionPreference.SilentlyContinue
            && preference != ActionPreference.Ignore;
    }

    internal static string? GetString(Hashtable table, string key) =>
        table.ContainsKey(key) ? table[key]?.ToString() : null;

    internal static int GetInt(Hashtable table, string key) {
        if (!table.ContainsKey(key)) {
            return 0;
        }

        var value = table[key];
        if (value is int number) {
            return number;
        }

        return int.TryParse(value?.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed)
            ? parsed
            : 0;
    }

    internal static bool? GetNullableBool(Hashtable table, string key) {
        if (!table.ContainsKey(key)) {
            return null;
        }

        var value = table[key];
        if (value is bool boolean) {
            return boolean;
        }

        return bool.TryParse(value?.ToString(), out var parsed) ? parsed : null;
    }

    internal static bool GetBool(Hashtable table, string key) =>
        GetNullableBool(table, key) ?? false;

    internal static ErrorCategory GetErrorCategory(Hashtable table, string key) {
        if (!table.ContainsKey(key)) {
            return ErrorCategory.NotSpecified;
        }

        var value = table[key];
        if (value is ErrorCategory category) {
            return category;
        }

        return Enum.TryParse<ErrorCategory>(value?.ToString(), ignoreCase: true, out var parsed)
            ? parsed
            : ErrorCategory.NotSpecified;
    }
}
