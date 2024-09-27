// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections.Concurrent;
using System.Management.Automation.Language;
using Compiler.Module.Compiled;
using Compiler.Requirements;
using Compiler.Text;
using Compiler.Text.Updater.Built;
using LanguageExt;

namespace Compiler.Module.Resolvable;

public partial class ResolvableLocalModule : Resolvable {
    private static readonly string TempModuleExportPath = Path.Combine(Path.GetTempPath(), "Compiler", "ExportedModules");
    private static readonly ConcurrentDictionary<string, Fin<string>> EmbeddedResources = [];

    internal readonly ScriptBlockAst RequirementsAst;

    public readonly TextEditor Editor;

    public override PathedModuleSpec ModuleSpec => (PathedModuleSpec)base.ModuleSpec;

    /// <summary>
    /// Creates a new LocalModule from the moduleSpec and a path to the root to find the path.
    /// </summary>
    /// <param name="parentPath">
    /// The root to resolve the path from, must be an absolute path.
    /// </param>
    /// <param name="moduleSpec">
    /// The module spec to create the module from.
    /// </param>
    /// <exception cref="AggregateException">
    /// Thrown when the ast cannot be generated from the file.
    /// </exception>
    /// <exception cref="InvalidModulePathError">
    /// Thrown when the path is not a valid module path.
    /// This may be because the path is not a file or
    /// the parent path is not an absolute path.
    /// </exception>
    public ResolvableLocalModule(
        string parentPath,
        ModuleSpec moduleSpec
    ) : this(
        moduleSpec is PathedModuleSpec pathedModuleSpec
            ? pathedModuleSpec
            : new PathedModuleSpec(Path.GetFullPath(Path.Combine(parentPath, moduleSpec.Name)))
        ) {
        if (!Path.IsPathRooted(parentPath)) throw InvalidModulePathError.NotAnAbsolutePath(parentPath);
        if (!Directory.Exists(parentPath)) throw InvalidModulePathError.ParentNotADirectory(parentPath);
    }

    /// <summary>
    /// Creates a new LocalModule from the moduleSpec.
    /// </summary>
    /// <param name="moduleSpec"></param>
    /// <exception cref="InvalidModulePathException">
    /// Thrown when the path is not a valid module path.
    /// </exception>
    /// <exception cref="AggregateException">
    /// Thrown when the ast cannot be generated from the file.
    /// </exception>
    public ResolvableLocalModule(PathedModuleSpec moduleSpec) : base(moduleSpec) {
        if (!File.Exists(moduleSpec.FullPath)) {
            throw InvalidModulePathError.NotAFile(moduleSpec.FullPath);
        }

        this.Editor = new TextEditor(new TextDocument(File.ReadAllLines(moduleSpec.FullPath)));
        this.RequirementsAst = this.Editor.Document.GetRequirementsAst().BindFail(err => err.Enrich(this.ModuleSpec)).ThrowIfFail();

        this.Editor.AddEdit(static () => new WhitespaceUpdater());
        this.Editor.AddEdit(static () => new CommentRemovalUpdater());
        this.Editor.AddEdit(static () => new HereStringUpdater());
    }

    /// <summary>
    /// Returns the module match for the given requirement.
    ///
    /// Module matches for Local files are based on only the name of the module.
    /// </summary>
    /// <param name="requirement">
    /// The requirement to match against.
    /// </param>
    /// <returns>
    /// The module match for the given requirement.
    /// </returns>
    public override ModuleMatch GetModuleMatchFor(ModuleSpec requirement) {
        // Local files have nothing but a name.
        if (this.ModuleSpec.Name == requirement.Name) {
            return ModuleMatch.Same;
        }

        return ModuleMatch.None;
    }

    public override Task<Option<Error>> ResolveRequirements() {
        string[] dontAddTo = ["Analyser", "ModuleUtils"];
        var foundAnalyserModule = dontAddTo.Contains(Path.GetFileNameWithoutExtension(this.ModuleSpec.Name));

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
            var spec = new ModuleSpec(
                module.Key,
                (Guid?)guid,
                (Version?)minimumVersion,
                (Version?)maximumVersion,
                (Version?)requiredVersion
            );

            if (spec.Name.EndsWith("Analyser.psm1", StringComparison.OrdinalIgnoreCase)) {
                foundAnalyserModule = true;
            }

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

        // TODO - Cleanup this fuckfest of a workaround.
        // Add a reference to the Analyser.psm1 file to ensure all files have access to the SuppressAnalyserAttribute
        if (!foundAnalyserModule) {
            lock (this.Requirements) {
                this.Requirements.AddRequirement(new ModuleSpec(GetExportedResource("ModuleUtils.psm1").Unwrap())); // Safety - We know this will always be present in the resources.
                this.Requirements.AddRequirement(new ModuleSpec(GetExportedResource("Analyser.psm1").Unwrap())); // Safety - We know this will always be present in the resources.
            }
        }

        return Option<Error>.None.AsTask();
    }

    public override Task<Fin<Compiled.Compiled>> IntoCompiled() => CompiledDocument.FromBuilder(this.Editor, 0)
        .BindFail(err => err.Enrich(this.ModuleSpec))
        .AndThenTry(doc => new CompiledLocalModule(
            this.ModuleSpec,
            doc,
            this.Requirements
        ) as Compiled.Compiled).AsTask();

    public override bool Equals(object? obj) {
        if (obj is null) return false;
        if (ReferenceEquals(this, obj)) return true;
        return obj is ResolvableLocalModule other &&
            this.ModuleSpec.CompareTo(other.ModuleSpec) == ModuleMatch.Same &&
            this.Editor.Document.GetLines() == other.Editor.Document.GetLines();
    }

    public override int GetHashCode() => this.ModuleSpec.GetHashCode();

    private static Fin<string> GetExportedResource(
        string moduleName
    ) => EmbeddedResources.GetOrAdd(moduleName, name => {
        var tempModulePath = Path.Combine(TempModuleExportPath, name);
        if (!Program.GetEmbeddedResource(name).IsSome(out var embeddedStream)) {
            return (Error)new FileNotFoundException($"The embedded resource {name} was not found.");
        }

        if (!Directory.Exists(TempModuleExportPath)) {
            Directory.CreateDirectory(TempModuleExportPath);
        }

        if (!Path.Exists(tempModulePath)) {
            using var fileWriter = File.OpenWrite(tempModulePath);
            embeddedStream.CopyTo(fileWriter);
        } else {
            // If the file exists, check if its contents are the same.
            using var fileStream = File.Open(tempModulePath, FileMode.Open);
            var streamsDiffer = embeddedStream.Length != fileStream.Length; // If the lengths are different, the streams are different.
            // If the lengths are the same, check the contents.
            while (!streamsDiffer && fileStream.Position < fileStream.Length) {
                streamsDiffer = embeddedStream.ReadByte() != fileStream.ReadByte();
            }

            if (streamsDiffer) {
                using var fileWriter = new StreamWriter(fileStream);
                fileWriter.Write(embeddedStream);
            }
        }

        embeddedStream.Close();
        return tempModulePath;
    });
}
