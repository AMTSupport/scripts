using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Temp;

/// <summary>Runs a script block inside a newly created ephemeral temporary folder.</summary>
/// <remarks>
/// Creates a unique temp folder, sets it as the working directory, invokes the script block,
/// then restores the original location and deletes the folder (best-effort) on completion
/// regardless of whether the script block throws.
/// </remarks>
/// <example>
/// <code>
/// Invoke-WithinEphemeral -ScriptBlock {
///     Invoke-WebRequest 'https://example.com/archive.zip' -OutFile 'archive.zip'
///     Expand-Archive 'archive.zip' -DestinationPath '.'
/// }
/// </code>
/// Downloads and extracts a file into a temp folder that is deleted afterwards.
/// </example>
[Cmdlet("Invoke", "WithinEphemeral")]
[OutputType(typeof(object))]
public sealed class InvokeWithinEphemeralCommand : PSCmdlet {
    /// <summary>
    /// Script block to execute inside the ephemeral folder;
    /// runs with the folder as the current working directory.
    /// </summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNull]
    public ScriptBlock ScriptBlock { get; set; } = null!;

    protected override void ProcessRecord() {
        var folder = TempFolderOperations.GetUnique();
        var originalLocation = this.SessionState.Path.CurrentLocation.Path;

        try {
            this.SessionState.Path.SetLocation(folder);
            var results = this.ScriptBlock.Invoke();
            this.WriteObject(results, enumerateCollection: true);
        } finally {
            this.SessionState.Path.SetLocation(originalLocation);
            TempFolderOperations.TryDelete(folder);
        }
    }
}
