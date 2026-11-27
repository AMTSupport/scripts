using System;
using System.Management.Automation;
using System.Runtime.InteropServices;

namespace AMT.PowerShell.Common.Commands.Ensure;

/// <summary>Terminate the pipeline if the current process is not running elevated as Administrator.</summary>
/// <remarks>
/// Windows-only; on non-Windows platforms the check is silently skipped.
/// Uses a P/Invoke call to query token elevation, so a <see cref="DllNotFoundException"/> or
/// <see cref="EntryPointNotFoundException"/> is treated as an indeterminate soft-pass.
/// </remarks>
/// <example>
/// <code>Invoke-EnsureAdministrator</code>
/// Throws a terminating PermissionDenied error when the session is not elevated.
/// </example>
[Cmdlet("Invoke", "EnsureAdministrator")]
public sealed class InvokeEnsureAdministratorCommand : PSCmdlet {
    protected override void ProcessRecord() {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) {
            this.WriteVerbose("Administrator check is not supported on non-Windows; skipping.");
            return;
        }

        bool isElevated;
        try {
            isElevated = EnsureNativeMethods.IsCurrentProcessElevated();
        } catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException) {
            this.WriteVerbose("Unable to determine elevation status; proceeding.");
            return;
        }

        if (isElevated) {
            return;
        }

        this.ThrowTerminatingError(new ErrorRecord(
            new UnauthorizedAccessException(
                "Not running as Administrator. Re-run your terminal session as Administrator and try again."),
            "AMT.Ensure.NotAdministrator",
            ErrorCategory.PermissionDenied,
            null));
    }
}
