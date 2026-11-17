// Copyright (c) 2024, 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.IO.Compression;
using System.Management.Automation.Language;
using Compiler.Module.Compiled;
using Compiler.Requirements;
using Compiler.Text;
using Compiler.Text.Updater.Built;
using LanguageExt;

namespace Compiler.Module.Resolvable;

public partial class ResolvableLocalModule : Resolvable {
    internal readonly ScriptBlockAst RequirementsAst;

    public readonly TextEditor Editor;

    public override PathedModuleSpec ModuleSpec => (PathedModuleSpec)base.ModuleSpec;

    private bool IsPackagedModulePath => string.Equals(Path.GetExtension(this.ModuleSpec.FullPath), ".psd1", StringComparison.OrdinalIgnoreCase) && Directory.Exists(Path.GetDirectoryName(this.ModuleSpec.FullPath)!);

    public ResolvableLocalModule(
        string parentPath,
        ModuleSpec moduleSpec
    ) : this(
        moduleSpec is PathedModuleSpec pathedModuleSpec
            ? pathedModuleSpec
            : new PathedModuleSpec(parentPath, moduleSpec.Name)
    ) {
        if (!Path.IsPathRooted(parentPath)) throw InvalidModulePathError.NotAnAbsolutePath(parentPath);
        if (!Directory.Exists(parentPath)) throw InvalidModulePathError.ParentNotADirectory(parentPath);
    }

    public ResolvableLocalModule(PathedModuleSpec moduleSpec) : base(moduleSpec) {
        if (!File.Exists(moduleSpec.FullPath)) {
            throw InvalidModulePathError.NotAFile(moduleSpec.FullPath);
        }

        if (this.IsPackagedModulePath) {
            this.Editor = new TextEditor(new TextDocument([]));
            this.RequirementsAst = Parser.ParseInput(string.Empty, out _, out _);
            return;
        }

        this.Editor = new TextEditor(new TextDocument(File.ReadAllLines(moduleSpec.FullPath)));
        this.RequirementsAst = this.Editor.Document.GetRequirementsAst().BindFail(err => err.Enrich(this.ModuleSpec)).ThrowIfFail();

        this.Editor.AddEdit(static () => new WhitespaceUpdater());
        this.Editor.AddEdit(static () => new CommentRemovalUpdater());
        this.Editor.AddEdit(static () => new HereStringUpdater());
    }

    [System.Diagnostics.Contracts.Pure]
    public override ModuleMatch GetModuleMatchFor(ModuleSpec requirement) => this.ModuleSpec.CompareTo(requirement);

    public override Task<Option<Error>> ResolveRequirements() {
        if (this.IsPackagedModulePath) {
            this.ReadPackagedManifestRequirements();
            return Option<Error>.None.AsTask();
        }

        AstHelper.FindDeclaredModules(this.RequirementsAst).ToList().ForEach(module => {
            if (module.Value.TryGetValue("AST", out var obj) && obj is Ast ast) {
                this.Editor.AddExactEdit(
                    5,
                    ast.Extent.StartLineNumber - 1,
                    ast.Extent.StartColumnNumber - 1,
                    ast.Extent.EndLineNumber - 1,
                    ast.Extent.EndColumnNumber - 1,
                    _ => []
                );
            }

            module.Value.TryGetValue("Guid", out var guid);
            module.Value.TryGetValue("MinimumVersion", out var minimumVersion);
            module.Value.TryGetValue("MaximumVersion", out var maximumVersion);
            module.Value.TryGetValue("RequiredVersion", out var requiredVersion);

            ModuleSpec spec;
            var parentPath = Directory.GetParent(this.ModuleSpec.FullPath)!.FullName;
            var normalisedModuleKey = module.Key.Replace('\\', Path.DirectorySeparatorChar).Replace('/', Path.DirectorySeparatorChar);
            var possibleKeyFullPath = Path.GetFullPath(Path.Join(parentPath, normalisedModuleKey));
            spec = File.Exists(possibleKeyFullPath)
                ? new PathedModuleSpec(this.ModuleSpec.SourceRoot, possibleKeyFullPath)
                : new ModuleSpec(
                    module.Key,
                    (Guid?)guid,
                    (Version?)minimumVersion,
                    (Version?)maximumVersion,
                    (Version?)requiredVersion
                );

            lock (this.Requirements) {
                this.Requirements.AddRequirement(spec);
            }

        });

        AstHelper.FindDeclaredNamespaces(this.RequirementsAst).ToList().ForEach(statement => {
            this.Editor.AddExactEdit(
                5,
                statement.Extent.StartLineNumber - 1,
                statement.Extent.StartColumnNumber - 1,
                statement.Extent.EndLineNumber - 1,
                statement.Extent.EndColumnNumber - 1,
                _ => []
            );

            var ns = new UsingNamespace(statement.Name.Value);
            lock (this.Requirements) {
                this.Requirements.AddRequirement(ns);
            }
        });

        if (this.RequirementsAst.ScriptRequirements is not null) {
            if (this.RequirementsAst.ScriptRequirements.IsElevationRequired) {
                lock (this.Requirements) {
                    this.Requirements.AddRequirement(new RunAsAdminRequirement());
                }
            }

            if (this.RequirementsAst.ScriptRequirements.RequiredPSEditions is not null and not { Count: 0 }) {
                var psEditionString = this.RequirementsAst.ScriptRequirements.RequiredPSEditions.First();
                var psEdition = Enum.Parse<PSEdition>(psEditionString, true);
                lock (this.Requirements) {
                    this.Requirements.AddRequirement(new PSEditionRequirement(psEdition));
                }
            }

            if (this.RequirementsAst.ScriptRequirements.RequiredPSVersion is not null) {
                lock (this.Requirements) {
                    this.Requirements.AddRequirement(new PSVersionRequirement(this.RequirementsAst.ScriptRequirements.RequiredPSVersion));
                }
            }
        }

        return Option<Error>.None.AsTask();
    }

    public override Task<Fin<Compiled.Compiled>> IntoCompiled(ResolvableParent resolvableParent) {
        if (this.IsPackagedModulePath) {
            var moduleFolder = Path.GetDirectoryName(this.ModuleSpec.FullPath)!;
            var bytes = CreatePackagedArchiveBytes(moduleFolder, this.ModuleSpec.Name);
            var manifest = this.GetPackagedManifest();
            return Task.FromResult<Fin<Compiled.Compiled>>(new CompiledLocalArchiveModule(this.ModuleSpec, this.Requirements, bytes, manifest) {
                ResolvableParent = resolvableParent
            });
        }

        return CompiledDocument.FromBuilder(this.Editor, 0)
            .BindFail(err => err.Enrich(this.ModuleSpec))
            .AndThenTry(doc => new CompiledLocalModule(
                this.ModuleSpec,
                doc,
                this.Requirements
            ) {
                ResolvableParent = resolvableParent
            } as Compiled.Compiled).AsTask();
    }

    public override bool Equals(object? obj) {
        if (obj is null) return false;
        if (ReferenceEquals(this, obj)) return true;
        return obj is ResolvableLocalModule other
            && this.ModuleSpec.CompareTo(other.ModuleSpec) == ModuleMatch.Same
            && this.Editor.Document.GetLines() == other.Editor.Document.GetLines();
    }

    public override int GetHashCode() => this.ModuleSpec.GetHashCode();

    private static byte[] CreatePackagedArchiveBytes(string sourceDirectory, string moduleName) {
        using var memoryStream = new MemoryStream();
        using (var archive = new System.IO.Compression.ZipArchive(memoryStream, System.IO.Compression.ZipArchiveMode.Create, true)) {
            var files = Directory.GetFiles(sourceDirectory, "*", SearchOption.AllDirectories)
                .Where(path => !string.Equals(Path.GetExtension(path), ".psd1", StringComparison.OrdinalIgnoreCase) || string.Equals(Path.GetFileName(path), $"{moduleName}.psd1", StringComparison.OrdinalIgnoreCase))
                .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
                .ToArray();

            foreach (var file in files) {
                var entryName = Path.GetRelativePath(sourceDirectory, file).Replace(Path.DirectorySeparatorChar, '/');
                var entry = archive.CreateEntry(entryName, CompressionLevel.Optimal);
                using var entryStream = entry.Open();
                using var fileStream = File.OpenRead(file);
                fileStream.CopyTo(entryStream);
            }
        }

        return memoryStream.ToArray();
    }
}
