// Copyright (c) 2024, 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections;
using System.Globalization;
using System.Text;

namespace Compiler.Helpers;

/// <summary>
/// Serializes PowerShell data structures (Hashtable, arrays, primitives) to valid .psd1 / PowerShell data syntax.
/// Replaces dependency on ObjectGraphTools ConvertTo-Expression for manifest serialization.
/// </summary>
internal static class Psd1Serializer {
    /// <summary>
    /// Serializes a <see cref="Hashtable"/> to a valid PowerShell data string (.psd1 format).
    /// </summary>
    internal static string Serialize(Hashtable table) => SerializeValue(table, indentLevel: 0);

    private static string SerializeValue(object? value, int indentLevel) => value switch {
        null => "$Null",
        string s => SerializeString(s),
        bool b => b ? "$True" : "$False",
        int i => i.ToString(CultureInfo.InvariantCulture),
        long l => l.ToString(CultureInfo.InvariantCulture),
        short s => s.ToString(CultureInfo.InvariantCulture),
        byte b => b.ToString(CultureInfo.InvariantCulture),
        double d => d.ToString(CultureInfo.InvariantCulture),
        float f => f.ToString(CultureInfo.InvariantCulture),
        decimal m => m.ToString(CultureInfo.InvariantCulture),
        Hashtable ht => SerializeHashtable(ht, indentLevel),
        Array arr => SerializeArray(arr, indentLevel),
        // Fallback for unknown types: stringify
        _ => SerializeString(value.ToString() ?? string.Empty)
    };

    private static string SerializeString(string value) {
        // Here-string for multiline values
        if (value.Contains('\n') || value.Contains('\r')) {
            return $"@'\n{value}\n'@";
        }

        // Single-quoted with '' escaping
        var escaped = value.Replace("'", "''");
        return $"'{escaped}'";
    }

    private static string SerializeHashtable(Hashtable table, int indentLevel) {
        if (table.Count == 0) return "@{ }";

        var indent = new string(' ', indentLevel * 4);
        var innerIndent = new string(' ', (indentLevel + 1) * 4);
        var sb = new StringBuilder();
        sb.AppendLine("@{");

        foreach (DictionaryEntry entry in table) {
            var key = entry.Key?.ToString() ?? string.Empty;
            var keyStr = IsBareKey(key) ? key : SerializeString(key);
            var valueStr = SerializeValue(entry.Value, indentLevel + 1);
            sb.Append(innerIndent).Append(keyStr).Append(" = ").AppendLine(valueStr);
        }

        sb.Append(indent).Append('}');
        return sb.ToString();
    }

    private static string SerializeArray(Array array, int indentLevel) {
        if (array.Length == 0) return "@()";

        var innerIndent = new string(' ', (indentLevel + 1) * 4);
        var items = new List<string>(array.Length);
        foreach (var item in array) {
            items.Add($"{innerIndent}{SerializeValue(item, indentLevel + 1)}");
        }

        var sb = new StringBuilder();
        sb.AppendLine("@(");
        sb.AppendLine(string.Join(",\n", items));
        sb.Append(new string(' ', indentLevel * 4) + ")");
        return sb.ToString();
    }

    /// <summary>
    /// Determines if a key can be written as a bare word (unquoted) in PowerShell data syntax.
    /// Simple identifier: starts with letter/underscore, contains only letters/digits/underscores.
    /// </summary>
    private static bool IsBareKey(string key) {
        if (string.IsNullOrEmpty(key)) return false;

        if (!char.IsLetter(key[0]) && key[0] != '_') return false;

        for (var i = 1; i < key.Length; i++) {
            if (!char.IsLetterOrDigit(key[i]) && key[i] != '_') return false;
        }

        return true;
    }
}
