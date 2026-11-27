// Copyright (c) 2024, 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections;
using System.Diagnostics.Contracts;
using Compiler.Requirements;
using LanguageExt;

namespace Compiler.Module.Compiled;

public sealed class CompiledLocalArchiveModule : CompiledArchiveModule {
    private readonly Hashtable Manifest;
    private readonly Version ManifestVersion;

    public CompiledLocalArchiveModule(
        PathedModuleSpec moduleSpec,
        RequirementGroup requirements,
        byte[] bytes,
        Hashtable manifest
    ) : base(moduleSpec, requirements, new Lazy<Fin<byte[]>>(() => bytes)) {
        this.Manifest = manifest;
        this.ManifestVersion = GetManifestVersion(manifest);
    }

    protected override string ArchiveModuleFolderName => this.ModuleSpec.Name;

    protected override string ArchiveEntryName => this.Manifest["RootModule"] switch {
        string rootModule when !string.IsNullOrWhiteSpace(rootModule) => rootModule,
        _ => $"{this.ModuleSpec.Name}.psm1"
    };

    public override Version Version => this.ManifestVersion;

    public override IEnumerable<string> GetExportedFunctions() {
        var exported = new List<string>();

        void Add(object? value) {
            switch (value) {
                case string s when !string.IsNullOrWhiteSpace(s) && s != "*":
                    exported.Add(s);
                    break;
                case string star when star == "*":
                    break;
                case object[] array:
                    foreach (var item in array) Add(item);
                    break;
            }
        }

        Add(this.Manifest["FunctionsToExport"]);
        Add(this.Manifest["CmdletsToExport"]);
        Add(this.Manifest["AliasesToExport"]);

        return exported.Distinct(StringComparer.OrdinalIgnoreCase);
    }

    private static Version GetManifestVersion(Hashtable manifest) {
        if (manifest["ModuleVersion"] is string versionString && Version.TryParse(versionString, out var version)) {
            return version;
        }

        return new Version(0, 0, 1);
    }
}
