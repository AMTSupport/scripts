// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Logging;

/// <summary>Writes a message to the host at the Debug level.</summary>
/// <remarks>
/// Suppressed when <c>$DebugPreference</c> is <c>SilentlyContinue</c> or <c>Ignore</c>.
/// Accepts either individual parameters (Splat set) or a pre-built hashtable (InputObject set).
/// </remarks>
/// <example>
/// <code>Invoke-Debug -Message "Entering loop" -UnicodePrefix "🐛"</code>
/// Writes the message in magenta with the debug prefix if DebugPreference allows it.
/// </example>
[Cmdlet(VerbsLifecycle.Invoke, "Debug", DefaultParameterSetName = "Splat")]
public sealed class InvokeDebugCommand : PSCmdlet {
    private const string DefaultPrefix = "\U0001F41B"; // 🐛
    private const string Colour = "Magenta";
    private const string PreferenceName = "DebugPreference";

    /// <summary>Hashtable of parameters to splat into the cmdlet; when provided, all other parameters are ignored.</summary>
    [Parameter(ParameterSetName = "InputObject", Position = 0, ValueFromPipeline = true)]
    public Hashtable? InputObject { get; set; }

    /// <summary>The message text to write to the host.</summary>
    [Parameter(ParameterSetName = "Splat", Position = 0, Mandatory = true, ValueFromPipelineByPropertyName = true)]
    [ValidateNotNullOrEmpty]
    public string Message { get; set; } = string.Empty;

    /// <summary>Unicode prefix to prepend to the message; defaults to 🐛 when omitted.</summary>
    [Parameter(ParameterSetName = "Splat", Position = 1, ValueFromPipelineByPropertyName = true)]
    [Alias("Prefix")]
    public string? UnicodePrefix { get; set; }

    /// <summary>When set, returns the formatted string to the pipeline instead of writing it to the host.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true)]
    public SwitchParameter PassThru { get; set; }

    protected override void ProcessRecord() {
        if (this.InputObject is not null) {
            this.EmitSplat(this.InputObject);
            return;
        }

        this.EmitLevel(this.Message, this.UnicodePrefix ?? DefaultPrefix, this.PassThru.IsPresent);
    }

    private void EmitSplat(Hashtable splat) {
        var message = LoggingHelper.GetString(splat, "Message") ?? string.Empty;
        var prefix = LoggingHelper.GetString(splat, "UnicodePrefix")
            ?? LoggingHelper.GetString(splat, "Prefix")
            ?? DefaultPrefix;
        var passThru = LoggingHelper.GetBool(splat, "PassThru");

        this.EmitLevel(message, prefix, passThru);
    }

    private void EmitLevel(string message, string prefix, bool passThru) {
        var preference = LoggingHelper.ReadPreference(this, PreferenceName);
        if (!LoggingHelper.ShouldWriteLevel(preference, infoStyle: false)) {
            return;
        }

        LoggingHelper.Emit(this, message, prefix, Colour, 0, passThru, null);
    }
}
