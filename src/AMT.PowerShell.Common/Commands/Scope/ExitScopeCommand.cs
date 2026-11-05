// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Scope;

/// <summary>Pops the current scope from the runspace scope stack.</summary>
/// <remarks>
/// Stops the elapsed-time stopwatch for the scope. When <c>$VerbosePreference</c> is
/// <c>Continue</c>, emits a formatted exit message showing the scope name, elapsed time,
/// and optionally the return value.
/// </remarks>
/// <example>
/// <code>
/// function Invoke-MyFunction {
///     Enter-Scope -Invocation $MyInvocation
///     $result = Get-Something
///     Exit-Scope -ReturnValue $result
///     return $result
/// }
/// </code>
/// Closes the scope and logs the return value in verbose mode.
/// </example>
[Cmdlet("Exit", "Scope")]
public sealed class ExitScopeCommand : PSCmdlet {
    /// <summary>
    /// Value to display in the verbose exit message; does not affect pipeline output.
    /// </summary>
    [Parameter]
    public object? ReturnValue { get; set; }

    protected override void ProcessRecord() {
        var runspace = ScopeStack.RequireRunspace();

        if (ScopeStack.TryPeek(runspace, out var frame) && frame is not null) {
            frame.Stopwatch.Stop();

            if (IsVerbose()) {
                var scopeName = ScopeStack.FormatName(runspace, isExit: true);
                var returnValue = ScopeFormatting.FormatValue(this.ReturnValue, formatter: null);

                var message = scopeName + "\nExecution Time: " + frame.Stopwatch.ElapsedMilliseconds + "ms";
                if (!string.IsNullOrEmpty(returnValue)) {
                    message += "\n" + returnValue;
                }

                this.WriteInformation("❮❮ " + message, Array.Empty<string>());
            }
        }

        ScopeStack.TryPop(runspace, out _);
    }

    private bool IsVerbose() {
        var value = this.SessionState.PSVariable.GetValue("VerbosePreference");
        if (value is ActionPreference preference) {
            return preference == ActionPreference.Continue;
        }

        return string.Equals(value?.ToString(), "Continue", StringComparison.OrdinalIgnoreCase);
    }
}
