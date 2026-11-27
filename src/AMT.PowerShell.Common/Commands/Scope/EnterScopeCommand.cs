// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Scope;

/// <summary>Pushes the caller's invocation onto the runspace scope stack.</summary>
/// <remarks>
/// Records the caller's <see cref="System.Management.Automation.InvocationInfo"/> and starts an
/// elapsed-time stopwatch for the scope. When <c>$VerbosePreference</c> is <c>Continue</c>,
/// emits a formatted entry message showing the scope name and bound parameters.
/// Pair with <c>Exit-Scope</c> to close the scope.
/// </remarks>
/// <example>
/// <code>
/// function Invoke-MyFunction {
///     Enter-Scope -Invocation $MyInvocation
///     # ... work ...
///     Exit-Scope
/// }
/// </code>
/// Wraps a function body in a named, timed scope.
/// </example>
[Cmdlet("Enter", "Scope")]
public sealed class EnterScopeCommand : PSCmdlet {
    /// <summary>Parameter names to omit from the verbose parameter listing.</summary>
    [Parameter]
    public string[]? IgnoreParams { get; set; }

    /// <summary>
    /// Explicit <see cref="System.Management.Automation.InvocationInfo"/> to record;
    /// defaults to the caller's <c>$MyInvocation</c> when omitted.
    /// </summary>
    [Parameter]
    public InvocationInfo? Invocation { get; set; }

    /// <summary>
    /// Hashtable mapping parameter names to script blocks that format their values in verbose output.
    /// </summary>
    [Parameter]
    public Hashtable? ArgumentFormatter { get; set; }

    /// <summary>
    /// When set, writes the formatted scope-entry message to the pipeline
    /// instead of the information stream.
    /// </summary>
    [Parameter]
    public SwitchParameter PassThru { get; set; }

    protected override void ProcessRecord() {
        var invocation = this.Invocation ?? ResolveCallerInvocation();
        var runspace = ScopeStack.RequireRunspace();

        ScopeStack.Push(runspace, invocation);

        if (!IsVerbose()) {
            return;
        }

        var scopeName = ScopeStack.FormatName(runspace, isExit: false);
        var parameters = ScopeFormatting.FormatParameters(invocation, this.IgnoreParams, this.ArgumentFormatter);

        var message = scopeName;
        if (!string.IsNullOrEmpty(parameters)) {
            message += "\n" + parameters;
        }

        var formatted = "❯❯ " + message;

        if (this.PassThru) {
            this.WriteObject(formatted);
        } else {
            this.WriteInformation(formatted, Array.Empty<string>());
        }
    }

    // $MyInvocation resolves through the session scope chain to the caller's
    // InvocationInfo, unlike MyInvocation which is the cmdlet's own frame.
    private InvocationInfo ResolveCallerInvocation() =>
        this.SessionState.PSVariable.GetValue("MyInvocation") as InvocationInfo ?? this.MyInvocation;

    private bool IsVerbose() {
        var value = this.SessionState.PSVariable.GetValue("VerbosePreference");
        if (value is ActionPreference preference) {
            return preference == ActionPreference.Continue;
        }

        return string.Equals(value?.ToString(), "Continue", StringComparison.OrdinalIgnoreCase);
    }
}
