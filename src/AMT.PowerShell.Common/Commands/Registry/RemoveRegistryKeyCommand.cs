using System;
using System.Collections.ObjectModel;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Registry;

/// <summary>Removes a registry value if it exists.</summary>
/// <remarks>
/// No-ops silently if the registry path or the named value does not exist.
/// Uses ShouldProcess to support -WhatIf and -Confirm.
/// Only supported on Windows.
/// </remarks>
/// <example>
/// <code>Remove-RegistryKey -Path 'HKLM:\SOFTWARE\MyApp' -Key 'OldSetting'</code>
/// Deletes the OldSetting value from HKLM:\SOFTWARE\MyApp.
/// </example>
[Cmdlet(VerbsCommon.Remove, "RegistryKey", SupportsShouldProcess = true)]
public sealed class RemoveRegistryKeyCommand : PSCmdlet {
    /// <summary>The registry path to the key container (e.g., <c>HKLM:\SOFTWARE\MyApp</c>).</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string Path { get; set; } = string.Empty;

    /// <summary>The name of the registry value to remove.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNullOrEmpty]
    public string Key { get; set; } = string.Empty;

    protected override void ProcessRecord() {
        if (!RegistryHelper.IsRegistrySupported) {
            RegistryHelper.WriteUnsupportedError(this);
            return;
        }

        if (!this.InvokeProvider.Item.Exists(this.Path)) {
            return;
        }

        bool valueExists;
        try {
            var props = this.InvokeProvider.Property.Get(
                this.Path,
                new Collection<string> { this.Key });
            valueExists = props.Count > 0 && props[0].Properties[this.Key] != null;
        } catch {
            valueExists = false;
        }

        if (!valueExists) {
            return;
        }

        if (!this.ShouldProcess(this.Path, $"Remove registry value '{this.Key}'")) {
            return;
        }

        this.InvokeProvider.Property.Remove(this.Path, this.Key);
    }
}
