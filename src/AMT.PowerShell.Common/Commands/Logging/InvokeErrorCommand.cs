// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Logging;

/// <summary>Writes a message to the host at the Error level, or throws a terminating error.</summary>
/// <remarks>
/// When <c>-Throw</c> is set the message is wrapped in an <see cref="ErrorRecord"/> and
/// passed to <c>ThrowTerminatingError</c>.
/// Otherwise the message is suppressed when <c>$ErrorActionPreference</c> is
/// <c>SilentlyContinue</c> or <c>Ignore</c>.
/// </remarks>
/// <example>
/// <code>Invoke-Error -Message "File not found" -Throw -ErrorCategory ObjectNotFound</code>
/// Throws a terminating error with the ObjectNotFound category.
/// </example>
[Cmdlet(VerbsLifecycle.Invoke, "Error", DefaultParameterSetName = "Splat")]
public sealed class InvokeErrorCommand : PSCmdlet {
    private const string DefaultPrefix = "\u274C"; // ❌
    private const string Colour = "Red";
    private const string PreferenceName = "ErrorActionPreference";
    private const string InformationTag = "AMT.ErrorDisplay";

    /// <summary>Hashtable of parameters to splat into the cmdlet; when provided, all other parameters are ignored.</summary>
    [Parameter(ParameterSetName = "InputObject", Position = 0, ValueFromPipeline = true)]
    public Hashtable? InputObject { get; set; }

    /// <summary>The error message text to write or throw.</summary>
    [Parameter(ParameterSetName = "Splat", Position = 0, Mandatory = true, ValueFromPipelineByPropertyName = true)]
    [ValidateNotNullOrEmpty]
    public string Message { get; set; } = string.Empty;

    /// <summary>Unicode prefix to prepend to the message; defaults to ❌ when omitted.</summary>
    [Parameter(ParameterSetName = "Splat", Position = 1, ValueFromPipelineByPropertyName = true)]
    [Alias("Prefix")]
    public string? UnicodePrefix { get; set; }

    /// <summary>When set, returns the formatted string to the pipeline instead of writing it to the host.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true)]
    public SwitchParameter PassThru { get; set; }

    /// <summary>When set, throws a terminating error instead of writing the message to the host.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true)]
    public SwitchParameter Throw { get; set; }

    /// <summary>The <see cref="ErrorCategory"/> to assign when <c>-Throw</c> is used; defaults to <c>NotSpecified</c>.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true)]
    public ErrorCategory ErrorCategory { get; set; } = ErrorCategory.NotSpecified;

    /// <summary>The caller's <see cref="InvocationInfo"/> used as the error target when throwing; resolved from the call stack when omitted.</summary>
    [Parameter(DontShow = true, ValueFromPipelineByPropertyName = true)]
    public InvocationInfo? Caller { get; set; }

    /// <summary>The <see cref="PSCmdlet"/> on whose behalf <c>ThrowTerminatingError</c> is called; defaults to this cmdlet.</summary>
    [Parameter(DontShow = true, ValueFromPipelineByPropertyName = true)]
    public PSCmdlet? CallerCmdlet { get; set; }

    protected override void ProcessRecord() {
        if (this.InputObject is not null) {
            this.ProcessSplat(this.InputObject);
            return;
        }

        if (this.Throw.IsPresent) {
            this.ThrowError(this.Message, this.ErrorCategory, this.Caller, this.CallerCmdlet);
            return;
        }

        var preference = LoggingHelper.ReadPreference(this, PreferenceName);
        if (!LoggingHelper.ShouldWriteLevel(preference, infoStyle: false)) {
            return;
        }

        LoggingHelper.Emit(
            this,
            this.Message,
            this.UnicodePrefix ?? DefaultPrefix,
            Colour,
            0,
            this.PassThru.IsPresent,
            InformationTag);
    }

    private void ProcessSplat(Hashtable splat) {
        var message = LoggingHelper.GetString(splat, "Message") ?? string.Empty;
        var prefix = LoggingHelper.GetString(splat, "UnicodePrefix")
            ?? LoggingHelper.GetString(splat, "Prefix")
            ?? DefaultPrefix;
        var passThru = LoggingHelper.GetBool(splat, "PassThru");
        var shouldThrow = LoggingHelper.GetBool(splat, "Throw");
        var errorCategory = LoggingHelper.GetErrorCategory(splat, "ErrorCategory");

        if (shouldThrow) {
            this.ThrowError(
                message,
                errorCategory,
                GetInvocationInfo(splat, "Caller"),
                GetCmdlet(splat, "CallerCmdlet"));
            return;
        }

        var preference = LoggingHelper.ReadPreference(this, PreferenceName);
        if (!LoggingHelper.ShouldWriteLevel(preference, infoStyle: false)) {
            return;
        }

        LoggingHelper.Emit(this, message, prefix, Colour, 0, passThru, InformationTag);
    }

    private void ThrowError(string message, ErrorCategory errorCategory, InvocationInfo? caller, PSCmdlet? callerCmdlet) {
        var errorRecord = new ErrorRecord(
            new InvalidOperationException(message),
            "Error",
            errorCategory,
            caller ?? this.MyInvocation);

        (callerCmdlet ?? this).ThrowTerminatingError(errorRecord);
    }

    private static InvocationInfo? GetInvocationInfo(Hashtable splat, string key) =>
        splat.ContainsKey(key) ? splat[key] as InvocationInfo : null;

    private static PSCmdlet? GetCmdlet(Hashtable splat, string key) =>
        splat.ContainsKey(key) ? splat[key] as PSCmdlet : null;
}
