using System;
using System.Management.Automation;
using System.Runtime.InteropServices;

namespace AMT.PowerShell.Common.Commands.Ensure;

/// <summary>Terminate the pipeline if the current process is running elevated as Administrator.</summary>
/// <remarks>
/// Windows-only; on non-Windows platforms the check is silently skipped.
/// Counterpart to <c>Invoke-EnsureAdministrator</c>: use this where a script must not run elevated.
/// A <see cref="DllNotFoundException"/> or <see cref="EntryPointNotFoundException"/> from the
/// P/Invoke elevation query is treated as an indeterminate soft-pass.
/// </remarks>
/// <example>
/// <code>Invoke-EnsureUser</code>
/// Throws a terminating PermissionDenied error when the session is elevated.
/// </example>
[Cmdlet("Invoke", "EnsureUser")]
public sealed class InvokeEnsureUserCommand : PSCmdlet {
    protected override void ProcessRecord() {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) {
            this.WriteVerbose("User check is not supported on non-Windows; skipping.");
            return;
        }

        bool isElevated;
        try {
            isElevated = EnsureNativeMethods.IsCurrentProcessElevated();
        } catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException) {
            this.WriteVerbose("Unable to determine elevation status; proceeding.");
            return;
        }

        if (!isElevated) {
            return;
        }

        this.ThrowTerminatingError(new ErrorRecord(
            new UnauthorizedAccessException(
                "Not running as a standard user. Re-run your terminal session as a normal user (not Administrator) and try again."),
            "AMT.Ensure.NotUser",
            ErrorCategory.PermissionDenied,
            null));
    }
}
