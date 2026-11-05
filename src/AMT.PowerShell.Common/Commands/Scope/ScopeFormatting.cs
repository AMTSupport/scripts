// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Scope;

internal static class ScopeFormatting {
    internal static string? FormatParameters(InvocationInfo invocation, string[]? ignoreParams, Hashtable? argumentFormatter) {
        var bound = invocation.BoundParameters;
        if (bound is null || bound.Count == 0) {
            return null;
        }

        var ignore = ignoreParams ?? Array.Empty<string>();
        var formatter = argumentFormatter ?? new Hashtable();

        var lines = new List<string>();
        foreach (var entry in bound) {
            if (ignore.Contains(entry.Key, StringComparer.OrdinalIgnoreCase)) {
                continue;
            }

            var script = LookupFormatter(formatter, entry.Key);
            var formattedValue = FormatValue(entry.Value, script);
            lines.Add($"{entry.Key} = {formattedValue}");
        }

        return lines.Count == 0 ? null : string.Join("\n", lines);
    }

    internal static string? FormatValue(object? value, ScriptBlock? formatter) {
        if (value is null) {
            return null;
        }

        if (formatter is not null) {
            var formatted = InvokeFormatter(formatter, value);
            if (formatted is not null) {
                return formatted;
            }
        }

        if (value is string text) {
            return text;
        }

        if (value is IDictionary dictionary) {
            var pairs = new List<string>();
            foreach (DictionaryEntry entry in dictionary) {
                pairs.Add($"{entry.Key} = {entry.Value}");
            }

            return "{" + string.Join(", ", pairs) + "}";
        }

        if (value is IEnumerable enumerable) {
            return "[" + string.Join(", ", enumerable.Cast<object?>().Select(item => item?.ToString() ?? string.Empty)) + "]";
        }

        return value.ToString() ?? string.Empty;
    }

    // Mirrors the legacy formatter contract where $_ is bound to the value.
    private static string? InvokeFormatter(ScriptBlock formatter, object? value) {
        try {
            var results = formatter.InvokeWithContext(null, new List<PSVariable> { new PSVariable("_", value) });
            return results.Count > 0 ? results[0]?.ToString() : string.Empty;
        } catch {
            return null;
        }
    }

    private static ScriptBlock? LookupFormatter(Hashtable formatter, string key) {
        foreach (DictionaryEntry entry in formatter) {
            if (string.Equals(entry.Key as string, key, StringComparison.OrdinalIgnoreCase)) {
                return entry.Value as ScriptBlock;
            }
        }

        return null;
    }
}
