// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Logging;

/// <summary>Writes a formatted, coloured message to the host or returns it as a string.</summary>
/// <remarks>
/// This is the low-level write helper used by all level-specific cmdlets.
/// When <c>ShouldWrite</c> is <c>false</c> the call is a no-op.
/// When <c>PassThru</c> is set the formatted string is returned to the pipeline instead.
/// An optional <c>InformationTag</c> is attached when writing to the information stream.
/// </remarks>
/// <example>
/// <code>Invoke-Write -PSMessage "Done" -PSColour "Green" -ShouldWrite $true</code>
/// Writes "Done" in green to the console.
/// </example>
/// <example>
/// <code>Invoke-Write @{ PSMessage = "Hello"; PSColour = "Cyan"; PassThru = $true }</code>
/// Returns the formatted string via the pipeline.
/// </example>
[Cmdlet(VerbsLifecycle.Invoke, "Write", DefaultParameterSetName = "Splat")]
public sealed class InvokeWriteCommand : PSCmdlet {
    /// <summary>Hashtable of parameters to splat into the cmdlet; when provided, all other parameters are ignored.</summary>
    [Parameter(ParameterSetName = "InputObject", Position = 0, ValueFromPipeline = true)]
    public Hashtable? InputObject { get; set; }

    /// <summary>The message text to format and write.</summary>
    [Parameter(ParameterSetName = "Splat", Mandatory = true, ValueFromPipelineByPropertyName = true)]
    [ValidateNotNullOrEmpty]
    public string PSMessage { get; set; } = string.Empty;

    /// <summary>Optional Unicode prefix (e.g., an emoji) to prepend to the message.</summary>
    [Parameter(ParameterSetName = "Splat", ValueFromPipelineByPropertyName = true)]
    public string? PSPrefix { get; set; }

    /// <summary>Console colour name for the message text (e.g., "Cyan", "Red").</summary>
    [Parameter(ParameterSetName = "Splat", Mandatory = true, ValueFromPipelineByPropertyName = true)]
    [ValidateNotNullOrEmpty]
    public string PSColour { get; set; } = string.Empty;

    /// <summary>Number of spaces to indent continuation lines of a multi-line message.</summary>
    [Parameter(ParameterSetName = "Splat", ValueFromPipelineByPropertyName = true)]
    public int MultiLineIndent { get; set; }

    /// <summary>When explicitly <c>false</c>, suppresses all output; <c>null</c> or <c>true</c> allows writing.</summary>
    [Parameter(ParameterSetName = "Splat", ValueFromPipelineByPropertyName = true)]
    public bool? ShouldWrite { get; set; }

    /// <summary>When set, returns the formatted string to the pipeline instead of writing it to the host.</summary>
    [Parameter(ParameterSetName = "Splat", ValueFromPipelineByPropertyName = true)]
    public SwitchParameter PassThru { get; set; }

    /// <summary>Optional tag attached to the information stream record, used to filter output downstream.</summary>
    [Parameter(ParameterSetName = "Splat", ValueFromPipelineByPropertyName = true)]
    public string? InformationTag { get; set; }

    protected override void ProcessRecord() {
        if (this.InputObject is not null) {
            this.WriteWithSplat(this.InputObject);
            return;
        }

        if (this.ShouldWrite.HasValue && !this.ShouldWrite.Value) {
            return;
        }

        this.WriteFormatted(
            this.PSMessage,
            this.PSPrefix,
            this.PSColour,
            this.MultiLineIndent,
            this.PassThru.IsPresent,
            this.InformationTag);
    }

    private void WriteWithSplat(Hashtable splat) {
        var message = LoggingHelper.GetString(splat, "PSMessage") ?? string.Empty;
        var prefix = LoggingHelper.GetString(splat, "PSPrefix");
        var colour = LoggingHelper.GetString(splat, "PSColour") ?? string.Empty;
        var multiLineIndent = LoggingHelper.GetInt(splat, "MultiLineIndent");
        var shouldWrite = LoggingHelper.GetNullableBool(splat, "ShouldWrite");
        var passThru = LoggingHelper.GetBool(splat, "PassThru");
        var informationTag = LoggingHelper.GetString(splat, "InformationTag");

        if (shouldWrite.HasValue && !shouldWrite.Value) {
            return;
        }

        this.WriteFormatted(message, prefix, colour, multiLineIndent, passThru, informationTag);
    }

    private void WriteFormatted(
        string message,
        string? prefix,
        string colour,
        int multiLineIndent,
        bool passThru,
        string? informationTag) =>
        LoggingHelper.Emit(this, message, prefix, colour, multiLineIndent, passThru, informationTag);
}
