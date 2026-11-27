using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Temp;

/// <summary>Creates and returns a new uniquely-named temporary folder under the system temp directory.</summary>
/// <remarks>
/// Each call generates a distinct folder path using a random or GUID-based name.
/// The caller is responsible for cleaning up the folder when finished.
/// Use <c>Invoke-WithinEphemeral</c> for automatic cleanup.
/// </remarks>
/// <example>
/// <code>$dir = Get-UniqueTempFolder</code>
/// Creates a new unique temp folder and returns its full path.
/// </example>
[Cmdlet(VerbsCommon.Get, "UniqueTempFolder")]
[OutputType(typeof(string))]
public sealed class GetUniqueTempFolderCommand : Cmdlet {
    protected override void ProcessRecord() {
        var folder = TempFolderOperations.GetUnique();
        this.WriteObject(folder);
    }
}
