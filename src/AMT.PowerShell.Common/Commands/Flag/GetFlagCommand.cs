using System.Management.Automation;
using AMT.PowerShell.Common.Module;

namespace AMT.PowerShell.Common.Commands;

/// <summary>Returns a <see cref="Flag"/> instance for the specified context name.</summary>
/// <remarks>
/// A flag is a persistent on-disk marker used to track whether a particular operation has
/// already been performed. The returned object exposes methods to test, set, and clear the flag.
/// </remarks>
/// <example>
/// <code>$flag = Get-Flag -Context 'SoftwareInstalled'</code>
/// Retrieves a flag object for the context <c>SoftwareInstalled</c>.
/// </example>
[Cmdlet(VerbsCommon.Get, "Flag")]
[OutputType(typeof(Flag))]
public sealed class GetFlagCommand : Cmdlet {
    /// <summary>Logical name that identifies this flag; used to derive the flag file path.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string Context { get; set; } = string.Empty;

    protected override void ProcessRecord() {
        this.WriteObject(new Flag(this.Context));
    }
}
