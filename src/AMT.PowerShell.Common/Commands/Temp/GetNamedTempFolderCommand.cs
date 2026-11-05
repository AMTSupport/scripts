using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Temp;

/// <summary>Returns the path to a named temporary folder, creating it if necessary.</summary>
/// <remarks>
/// The folder is created under the system temp directory using the supplied name as a
/// subdirectory. The folder persists between calls unless -ForceEmpty is specified,
/// which clears its contents before returning the path.
/// </remarks>
/// <example>
/// <code>$dir = Get-NamedTempFolder -Name 'MyScript'</code>
/// Returns (or creates) a stable temp folder named MyScript.
/// </example>
/// <example>
/// <code>$dir = Get-NamedTempFolder -Name 'MyScript' -ForceEmpty</code>
/// Returns the MyScript temp folder after removing any existing contents.
/// </example>
[Cmdlet(VerbsCommon.Get, "NamedTempFolder")]
[OutputType(typeof(string))]
public sealed class GetNamedTempFolderCommand : Cmdlet {
    /// <summary>Logical name used as the subdirectory name within the system temp directory.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string Name { get; set; } = string.Empty;

    /// <summary>When set, removes all existing contents from the folder before returning its path.</summary>
    [Parameter]
    public SwitchParameter ForceEmpty { get; set; }

    protected override void ProcessRecord() {
        var folder = TempFolderOperations.GetNamed(this.Name, this.ForceEmpty.IsPresent);
        this.WriteObject(folder);
    }
}
