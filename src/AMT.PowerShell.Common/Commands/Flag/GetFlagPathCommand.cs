using System.Management.Automation;
using AMT.PowerShell.Common.Module;

namespace AMT.PowerShell.Common.Commands;

/// <summary>Returns the absolute file-system path for a flag identified by context name.</summary>
/// <remarks>
/// Delegates path resolution to <c>FlagPathResolver</c>; the returned string can be used
/// directly with file-system cmdlets or passed to lower-level flag operations.
/// </remarks>
/// <example>
/// <code>$path = Get-FlagPath -Context 'SoftwareInstalled'</code>
/// Returns the full path to the flag file for context <c>SoftwareInstalled</c>.
/// </example>
[Cmdlet(VerbsCommon.Get, "FlagPath")]
[OutputType(typeof(string))]
public sealed class GetFlagPathCommand : Cmdlet {
    /// <summary>Logical name that identifies this flag; used to derive the flag file path.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string Context { get; set; } = string.Empty;

    protected override void ProcessRecord() {
        this.WriteObject(FlagPathResolver.GetFlagPath(this.Context));
    }
}
