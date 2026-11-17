using System;
using System.Collections.ObjectModel;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Registry;

/// <summary>Returns <see langword="true"/> if a registry value exists, <see langword="false"/> otherwise.</summary>
/// <remarks>
/// Returns <see langword="false"/> if the registry path itself does not exist.
/// Only supported on Windows.
/// </remarks>
/// <example>
/// <code>Test-RegistryKey -Path 'HKLM:\SOFTWARE\MyApp' -Key 'Enabled'</code>
/// Returns $true if the Enabled value is present under HKLM:\SOFTWARE\MyApp.
/// </example>
[Cmdlet("Test", "RegistryKey")]
[OutputType(typeof(bool))]
public sealed class TestRegistryKeyCommand : PSCmdlet {
    /// <summary>The registry path to the key container (e.g., <c>HKLM:\SOFTWARE\MyApp</c>).</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string Path { get; set; } = string.Empty;

    /// <summary>The name of the registry value to test for existence.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNullOrEmpty]
    public string Key { get; set; } = string.Empty;

    protected override void ProcessRecord() {
        if (!RegistryHelper.IsRegistrySupported) {
            RegistryHelper.WriteUnsupportedError(this);
            return;
        }

        if (!this.InvokeProvider.Item.Exists(this.Path)) {
            this.WriteObject(false);
            return;
        }

        bool hasValue;
        try {
            var props = this.InvokeProvider.Property.Get(
                this.Path,
                new Collection<string> { this.Key });
            hasValue = props.Count > 0 && props[0].Properties[this.Key] != null;
        } catch {
            hasValue = false;
        }

        this.WriteObject(hasValue);
    }
}
