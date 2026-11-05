// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Management.Automation;
using System.Reflection;
using System.Text;

namespace AMT.PowerShell.Common.Commands.Logging;

/// <summary>Formats an <see cref="InvocationInfo"/> or <see cref="ErrorRecord"/> into human-readable diagnostic rows.</summary>
/// <remarks>
/// Produces labelled rows for File, Where, Preview, and Message.
/// When PassThru is set the rows are returned as strings instead of written to the information stream.
/// </remarks>
/// <example>
/// <code>Format-Error -InvocationInfo $MyInvocation -Message "Unexpected state"</code>
/// Writes formatted diagnostic rows for the current invocation.
/// </example>
[Cmdlet(VerbsCommon.Format, "Error")]
public sealed class FormatErrorCommand : PSCmdlet {
    private const string InformationTag = "AMT.ErrorDisplay";
    private const string UnknownFile = "Unknown";

    /// <summary>The invocation info of the error to format.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "InvocationInfo")]
    [ValidateNotNull]
    public InvocationInfo? InvocationInfo { get; set; }

    /// <summary>The error record to format; accepts <c>ParseError</c> or any object exposing an <c>Extent</c> property.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "ErrorRecord")]
    [ValidateNotNull]
    public object? ErrorRecord { get; set; }

    /// <summary>An optional message to append to the formatted output rows.</summary>
    [Parameter]
    [AllowNull]
    public string? Message { get; set; }

    /// <summary>Unicode prefix to prepend to the output if the terminal supports Unicode.</summary>
    [Parameter]
    [Alias("Prefix")]
    public string? UnicodePrefix { get; set; }

    /// <summary>When set, returns the formatted rows as strings instead of writing them to the information stream.</summary>
    [Parameter]
    public SwitchParameter PassThru { get; set; }

    /// <summary>Number of extra source lines to include around the error location in the Preview row.</summary>
    [Parameter]
    public int PreviewExtraLines { get; set; } = 5;

    protected override void ProcessRecord() {
        var rows = this.ParameterSetName == "InvocationInfo"
            ? this.BuildInvocationRows(this.InvocationInfo!)
            : BuildErrorRecordRows(this.ErrorRecord!);

        foreach (var row in rows) {
            if (this.PassThru.IsPresent) {
                this.WriteObject(row);
            } else {
                this.WriteInformation(row, new[] { InformationTag });
            }
        }
    }

    private IReadOnlyList<string> BuildInvocationRows(InvocationInfo info) {
        var file = string.IsNullOrWhiteSpace(info.ScriptName) ? UnknownFile : info.ScriptName;
        var line = info.Line?.Trim() ?? string.Empty;
        var where = FormatWhere(
            info.ScriptLineNumber,
            info.ScriptLineNumber,
            info.OffsetInLine,
            info.OffsetInLine + line.Length);
        var message = this.Message ?? string.Empty;

        return BuildRows(file, where, line, message);
    }

    private static IReadOnlyList<string> BuildErrorRecordRows(object record) {
        var message = ReadProperty(record, "Message") ?? string.Empty;
        var extent = GetProperty(record, "Extent");

        var file = ReadProperty(extent, "File") ?? UnknownFile;
        var startLine = ReadIntProperty(extent, "StartLineNumber");
        var endLine = ReadIntProperty(extent, "EndLineNumber");
        var startColumn = ReadIntProperty(extent, "StartColumnNumber");
        var endColumn = ReadIntProperty(extent, "EndColumnNumber");
        var preview = ReadProperty(extent, "Text") ?? string.Empty;

        var where = FormatWhere(startLine, endLine, startColumn, endColumn);
        return BuildRows(file, where, preview, message);
    }

    private static IReadOnlyList<string> BuildRows(string file, string where, string preview, string message) {
        var labels = new[] { "File", "Where", "Preview", "Message" };
        var values = new[] { file, where, preview, message };
        var padding = labels.Max(static label => label.Length) + 1;

        var rows = new List<string>();
        for (var i = 0; i < labels.Length; i++) {
            if (string.IsNullOrEmpty(values[i])) {
                continue;
            }

            rows.Add($"{labels[i]}{new string(' ', padding - labels[i].Length)}| {values[i]}");
        }

        return rows.Count == 0 ? new[] { UnknownFile } : rows;
    }

    private static string FormatWhere(int startLine, int endLine, int startColumn, int endColumn) {
        var builder = new StringBuilder();
        if (startLine != 0) {
            builder.Append(startLine);
        }

        if (startColumn != 0) {
            builder.Append('[').Append(startColumn);
        }

        if (endLine != startLine) {
            builder.Append("]..").Append(endLine);
            if (endColumn != 0) {
                builder.Append('[').Append(endColumn).Append(']');
            }
        } else if (endColumn != startColumn) {
            builder.Append("..").Append(endColumn).Append(']');
        } else if (startColumn != 0) {
            builder.Append(']');
        } else if (endColumn != 0) {
            builder.Append('[').Append(endColumn).Append(']');
        }

        return builder.ToString();
    }

    private static object? GetProperty(object? target, string name) =>
        target?.GetType().GetProperty(name, BindingFlags.Public | BindingFlags.Instance)?.GetValue(target);

    private static string? ReadProperty(object? target, string name) =>
        GetProperty(target, name)?.ToString();

    private static int ReadIntProperty(object? target, string name) {
        var value = GetProperty(target, name);
        return value is int number
            ? number
            : int.TryParse(value?.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed)
                ? parsed
                : 0;
    }
}
