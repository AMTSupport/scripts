using System;
using System.Collections.ObjectModel;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Registry;

/// <summary>Retrieves the value of a registry property at the specified path.</summary>
/// <remarks>
/// Returns <see langword="null"/> if the registry path does not exist or the named value
/// is not present under that path. Only supported on Windows.
/// </remarks>
/// <example>
/// <code>Get-RegistryKey -Path 'HKLM:\SOFTWARE\MyApp' -Key 'Version'</code>
/// Reads the Version value from HKLM:\SOFTWARE\MyApp.
/// </example>
[Cmdlet(VerbsCommon.Get, "RegistryKey")]
[OutputType(typeof(object))]
public sealed class GetRegistryKeyCommand : PSCmdlet {
    /// <summary>The registry path to the key container (e.g., <c>HKLM:\SOFTWARE\MyApp</c>).</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string Path { get; set; } = string.Empty;

    /// <summary>The name of the registry value to retrieve.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNullOrEmpty]
    public string Key { get; set; } = string.Empty;

    protected override void ProcessRecord() {
        if (!RegistryHelper.IsRegistrySupported) {
            RegistryHelper.WriteUnsupportedError(this);
            return;
        }

        if (!this.InvokeProvider.Item.Exists(this.Path)) {
            this.WriteObject(null);
            return;
        }

        object? value = null;
        try {
            var props = this.InvokeProvider.Property.Get(
                this.Path,
                new Collection<string> { this.Key });
            value = props.Count > 0 ? props[0].Properties[this.Key]?.Value : null;
        } catch {
            value = null;
        }

        this.WriteObject(value);
    }
}
