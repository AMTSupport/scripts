// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Reflection;

namespace AMT.PowerShell.Common.Commands.ModuleUtils;

/// <summary>Registers .NET types as PowerShell type accelerators and auto-removes them when the module unloads.</summary>
/// <remarks>
/// Each type's <c>FullName</c> is used as the accelerator key.
/// A cleanup callback is registered via <c>Add-ModuleCallback</c> so accelerators are removed
/// when the owning module is removed from the session.
/// Throws a terminating error if an accelerator key is already claimed by another module,
/// unless <c>-Clobber</c> is set.
/// </remarks>
/// <example>
/// <code>Export-Types -Types ([MyNamespace.MyClass], [MyNamespace.OtherClass])</code>
/// Registers both types as accelerators scoped to the calling module.
/// </example>
[Cmdlet(VerbsData.Export, "Types")]
public sealed class ExportTypesCommand : PSCmdlet {
    private const string ExportedTypesName = "__amt_exported_types";
    private const string AcceleratorsTypeName = "__amt_type_accelerators";

    /// <summary>Array of .NET <see cref="Type"/> objects to register as type accelerators.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public Type[] Types { get; set; } = [];

    /// <summary>When set, overwrites existing accelerators without throwing a conflict error.</summary>
    [Parameter]
    public SwitchParameter Clobber { get; set; }

    /// <summary>The module that owns the exported types; resolved from the call stack when omitted.</summary>
    [Parameter(Position = 1)]
    public PSModuleInfo? Module { get; set; }

    protected override void EndProcessing() {
        var module = ResolveModule();
        if (module is null) {
            ThrowTerminatingError(new ErrorRecord(
                new InvalidOperationException("This function must be called from within a module."),
                "ExportTypesRequiresModule",
                ErrorCategory.InvalidOperation,
                null));
            return;
        }

        var accelerators = TypeAccelerators.Get();

        if (!this.Clobber) {
            foreach (var type in this.Types) {
                var name = type.FullName;
                if (name is null || !accelerators.TryGetValue(name, out var existing)) {
                    continue;
                }

                if (IsOwnedByModule(existing, module)) {
                    continue;
                }

                var message =
                    $"Unable to register type accelerator '{name}' - Accelerator already exists.";
                ThrowTerminatingError(new ErrorRecord(
                    new InvalidOperationException(message),
                    "TypeAcceleratorAlreadyExists",
                    ErrorCategory.InvalidOperation,
                    name));
            }
        }

        foreach (var type in this.Types) {
            if (type.FullName is not null) {
                TypeAccelerators.Add(type.FullName, type);
            }
        }

        ModuleCallback.Add(module, BuildCleanupCallback(this.Types), this.SessionState);
    }

    private PSModuleInfo? ResolveModule() {
        if (this.Module is not null) {
            return this.Module;
        }

        return CallerModuleResolver.Resolve(this);
    }

    private ScriptBlock BuildCleanupCallback(Type[] types) {
        var acceleratorsType = TypeAccelerators.AcceleratorsTypeRef
            ?? throw new InvalidOperationException("Unable to resolve the internal TypeAccelerators type.");

        return ModuleCallback.CreateClosure(
            this.SessionState,
            "foreach ($Type in $__amt_exported_types) { $null = $__amt_type_accelerators::Remove($Type.FullName) }",
            new Dictionary<string, object?> {
                [ExportedTypesName] = types,
                [AcceleratorsTypeName] = acceleratorsType
            });
    }

    // A type accelerator is owned by the module whose script produced the type.
    // Script-compiled types carry an assembly-level ScriptFile attribute that
    // points at the originating module path.
    private static bool IsOwnedByModule(Type existingType, PSModuleInfo module) {
        var modulePath = module.Path;
        if (string.IsNullOrEmpty(modulePath)) {
            return false;
        }

        var assembly = existingType.Module?.Assembly;
        if (assembly is null) {
            return false;
        }

        foreach (var attribute in assembly.CustomAttributes) {
            foreach (var argument in attribute.NamedArguments) {
                if (argument.MemberName != "ScriptFile") {
                    continue;
                }

                if (argument.TypedValue.Value is string loadingFile
                    && string.Equals(loadingFile, modulePath, StringComparison.Ordinal)) {
                    return true;
                }
            }
        }

        return false;
    }
}
