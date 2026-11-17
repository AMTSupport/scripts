using System;
using System.Collections.ObjectModel;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Registry;

/// <summary>
/// Registry value kind; maps to values accepted by PowerShell's registry provider -Type parameter.
/// </summary>
public enum RegistryValueKind {
    Binary,
    DWord,
    ExpandString,
    MultiString,
    None,
    QWord,
    String,
    Unknown
}

/// <summary>Creates or updates a registry value, creating intermediate key nodes as needed.</summary>
/// <remarks>
/// If the target value already exists it is updated in place; otherwise a new value is created
/// with the specified type. All intermediate registry path segments are created if absent.
/// Uses ShouldProcess to support -WhatIf and -Confirm.
/// Only supported on Windows.
/// </remarks>
/// <example>
/// <code>Set-RegistryKey -Path 'HKLM:\SOFTWARE\MyApp' -Key 'Enabled' -Value 1 -Kind DWord</code>
/// Creates or updates the Enabled DWord value under HKLM:\SOFTWARE\MyApp.
/// </example>
[Cmdlet(VerbsCommon.Set, "RegistryKey", SupportsShouldProcess = true)]
public sealed class SetRegistryKeyCommand : PSCmdlet {
    /// <summary>The registry path to the key container (e.g., <c>HKLM:\SOFTWARE\MyApp</c>).</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string Path { get; set; } = string.Empty;

    /// <summary>The name of the registry value to create or update.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNullOrEmpty]
    public string Key { get; set; } = string.Empty;

    /// <summary>The data to write to the registry value.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public object Value { get; set; } = null!;

    /// <summary>The registry value type (e.g., DWord, String, ExpandString).</summary>
    [Parameter(Mandatory = true, Position = 3)]
    public RegistryValueKind Kind { get; set; }

    protected override void ProcessRecord() {
        if (!RegistryHelper.IsRegistrySupported) {
            RegistryHelper.WriteUnsupportedError(this);
            return;
        }

        if (!this.ShouldProcess(this.Path, $"Set registry value '{this.Key}'")) {
            return;
        }

        // Create intermediate registry keys as needed.
        EnsureRegistryPath(this.Path);

        bool valueExists;
        try {
            var props = this.InvokeProvider.Property.Get(
                this.Path,
                new Collection<string> { this.Key });
            valueExists = props.Count > 0 && props[0].Properties[this.Key] != null;
        } catch {
            valueExists = false;
        }

        if (valueExists) {
            var propObject = new PSObject();
            propObject.Properties.Add(new PSNoteProperty(this.Key, this.Value));
            this.InvokeProvider.Property.Set(this.Path, propObject);
        } else {
            // Property.New accepts the registry value-type name as a string.
            this.InvokeProvider.Property.New(
                this.Path, this.Key, this.Kind.ToString(), this.Value);
        }
    }

    // Walks the path segments and creates any missing registry key nodes.
    private void EnsureRegistryPath(string registryPath) {
        var separators = new[] { '\\', '/' };
        var segments = registryPath.Split(separators, StringSplitOptions.RemoveEmptyEntries);

        var current = segments[0]; // e.g., "HKLM:"
        for (var i = 1; i < segments.Length; i++) {
            current = current + "\\" + segments[i];
            if (!this.InvokeProvider.Item.Exists(current)) {
                this.InvokeProvider.Item.New(current, null, null, null);
            }
        }
    }
}
