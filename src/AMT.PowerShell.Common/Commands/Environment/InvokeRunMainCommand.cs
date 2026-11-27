// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections;
using System.Collections.ObjectModel;
using System.Management.Automation;
using AMT.PowerShell.Common.Commands.Exit;

namespace AMT.PowerShell.Common.Commands.EnvironmentCmdlets;

/// <summary>Run a script's main entry-point block with lifecycle management, restart support, and exit-code handling.</summary>
/// <remarks>
/// Applies <c>Set-StrictMode -Version 3</c> and prints a legal disclaimer before invoking <see cref="Main"/>,
/// unless suppressed via <see cref="NotStrict"/> or <see cref="HideDisclaimer"/>.
/// Handles the <c>QuickExit</c>, <c>FailedExit</c>, and <c>RestartScript</c> control-flow error signals,
/// and always invokes registered exit handlers when the run loop terminates.
/// Bound parameters from the calling <see cref="Cmdlet"/> are splatted onto <see cref="Main"/>.
/// </remarks>
/// <example>
/// <code>Invoke-RunMain -Cmdlet $PSCmdlet -Main { Write-Host 'Hello' }</code>
/// Runs the script block as the script entry point with strict mode and the disclaimer enabled.
/// </example>
[Cmdlet("Invoke", "RunMain")]
public sealed class InvokeRunMainCommand : PSCmdlet {
    /// <summary>Calling cmdlet context; its bound parameters are splatted onto <see cref="Main"/>.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public PSCmdlet Cmdlet { get; set; } = null!;

    /// <summary>Script block executed as the script's entry point.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNull]
    public ScriptBlock Main { get; set; } = null!;

    /// <summary>When set, skips applying <c>Set-StrictMode -Version 3</c> to the runspace before Main runs.</summary>
    [Parameter]
    public SwitchParameter NotStrict { get; set; }

    /// <summary>When set, suppresses the legal disclaimer message printed before Main runs.</summary>
    [Parameter]
    public SwitchParameter HideDisclaimer { get; set; }

    protected override void ProcessRecord() {
        if (!this.NotStrict.IsPresent) {
            EnvironmentRuntime.ApplyStrictMode(this);
        }

        if (!this.HideDisclaimer.IsPresent) {
            EnvironmentRuntime.ShowDisclaimer(this);
        }

        this.RunMainWithRestarts();
    }

    private void RunMainWithRestarts() {
        var runspace = EnvironmentStore.RequireRunspace();

        while (true) {
            var restart = false;
            var failure = false;
            try {
                this.WriteVerbose("🚀 Running main function.");
                this.InvokeEntrypoint(this.Main, this.Cmdlet.MyInvocation.BoundParameters);
                this.WriteInformation("Main function finished successfully.", Array.Empty<string>());
            } catch (RuntimeException exception) {
                (restart, failure) = this.HandleEntrypointError(exception);
            }

            // Mirrors the legacy teardown in Remove-FinishedModule; handlers run
            // once per runspace even across restarts.
            ExitHandlerRunner.Invoke(runspace, failure, this.WriteDebug, this.WriteWarning);

            if (!restart) {
                return;
            }

            EnvironmentStore.Reset(runspace);
        }
    }


    private void InvokeEntrypoint(ScriptBlock block, IDictionary? parameters) {
        var results = parameters is { Count: > 0 }
            ? InvokeWithSplat(block, parameters)
            : block.Invoke();

        if (results is not { Count: > 0 }) {
            return;
        }

        foreach (var result in results) {
            this.WriteObject(result);
        }
    }

    // Mirrors the legacy `& $Main @Parameters` call shape: splat the caller's
    // bound parameters onto Main as named arguments.
    private static Collection<PSObject> InvokeWithSplat(ScriptBlock block, IDictionary parameters) {
        var wrapper = ScriptBlock.Create("param($__main, $__parameters) & $__main @__parameters");
        return wrapper.Invoke(block, new Hashtable(parameters));
    }

    // Restart tells the loop to run Main again; failure tells exit handlers
    // whether the run is being torn down after an uncaught error.
    private (bool Restart, bool Failure) HandleEntrypointError(RuntimeException exception) {
        ErrorRecord? deepest = null;

        // ScriptBlock.Invoke wraps terminating errors in MethodInvocationException
        // / CmdletInvocationException; walk to the real control-flow error record.
        for (var current = (Exception?)exception; current is not null; current = current.InnerException) {
            if (current is not RuntimeException runtime || runtime.ErrorRecord is not { } error) {
                continue;
            }

            var route = this.TryRouteError(error);
            if (route.Handled) {
                return (route.Restart, false);
            }

            deepest ??= error;
        }

        var exitCode = exception is ParseException ? 9998 : 9999;
        EnvironmentRuntime.SetLastExitCode(this, exitCode);
        this.WriteError(deepest ?? new ErrorRecord(exception, "RunMainError", ErrorCategory.NotSpecified, null));
        return (false, true);
    }

    private (bool Handled, bool Restart) TryRouteError(ErrorRecord error) {
        if (IsErrorId(error, "QuickExit")) {
            this.WriteVerbose("✅ Main function finished successfully.");
            return (true, false);
        }

        if (IsErrorId(error, "FailedExit")) {
            if (error.TargetObject is int exitCode) {
                this.WriteVerbose($"Script exited with an error code of {exitCode}.");
                EnvironmentRuntime.SetLastExitCode(this, exitCode);
            }

            return (true, false);
        }

        if (IsErrorId(error, "RestartScript")) {
            EnvironmentRuntime.SetRestarting(this, true);
            return (true, true);
        }

        return (false, false);
    }

    // FullyQualifiedErrorId appends the command name after the error id, so match
    // the leading id rather than the whole string (e.g. QuickExit,InvokeQuickExitCommand).
    private static bool IsErrorId(ErrorRecord error, string id) {
        var qualified = error.FullyQualifiedErrorId;
        return string.Equals(qualified, id, StringComparison.Ordinal)
            || qualified.StartsWith(id + ",", StringComparison.Ordinal);
    }
}
