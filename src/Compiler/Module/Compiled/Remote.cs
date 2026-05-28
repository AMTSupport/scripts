// Copyright (c) 2024, 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections;
using System.IO.Compression;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Text;
using System.Text.Json;
using CommandLine;
using Compiler.Helpers;
using Compiler.Requirements;
using LanguageExt;
using NLog;

namespace Compiler.Module.Compiled;

public class CompiledRemoteModule : Compiled, IDisposable {

    private sealed record ExtraModuleInfo(
        string[]? FunctionsToExport,
        string[]? CmdletsToExport,
        string[]? AliasesToExport
    ) {
        public static readonly ExtraModuleInfo Empty = new(null, null, null);
    };

    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private static readonly JsonSerializerOptions JsonSerializerOptions = new() {
        ReadCommentHandling = JsonCommentHandling.Skip
    };
    private static readonly string RewritingFolder = Path.Join(Path.GetTempPath(), "PowerShellGet", "Rewriting");
    private readonly Lazy<ExtraModuleInfo> ThisExtraModuleInfo;
    private Hashtable? PowerShellManifest;
    private ZipArchive? ZipArchive;

    private Lock UpdatingArchiveLock { get; } = new();
    private Option<byte[]> UpdatedContentBytes;

    public override ContentType Type => ContentType.Zip;

    public override Version Version { get; }

    public CompiledRemoteModule(
        ModuleSpec moduleSpec,
        RequirementGroup requirements,
        byte[] bytes
    ) : base(moduleSpec, requirements, new Lazy<Fin<byte[]>>(() => bytes)) {
        var manifest = this.GetPowerShellManifest();
        this.Version = manifest["ModuleVersion"] switch {
            string version => Version.Parse(version),
            null => new Version(0, 0, 1),
            var other => throw new InvalidDataException($"ModuleVersion must be a string, but was {other.GetType()}")
        };

        this.ThisExtraModuleInfo = new(() => {
            var info = Assembly.GetExecutingAssembly().GetName();
            var extraModuleInfoResource = $"{info.Name}.Resources.ExtraModuleInfo.{this.ModuleSpec.Name}.json";
            using var templateStream = Assembly.GetExecutingAssembly().GetManifestResourceStream(extraModuleInfoResource)
                ?? Assembly.GetExecutingAssembly().GetManifestResourceStream($"{extraModuleInfoResource}c");
            if (templateStream == null) return ExtraModuleInfo.Empty;

            using var streamReader = new StreamReader(templateStream, Encoding.UTF8);
            return JsonSerializer.Deserialize<ExtraModuleInfo>(streamReader.ReadToEnd(), JsonSerializerOptions)
                ?? ExtraModuleInfo.Empty;
        });
    }

    public override void CompleteCompileAfterResolution() => this.UpdateArchiveContents();

    public override Fin<string> StringifyContent() {
        this.UpdateArchiveContents();
        var base64 = Convert.ToBase64String(this.UpdatedContentBytes.Unwrap());
        return $"'{base64}'";
    }

    // TODO - Cache the results of this function
    public IEnumerable<string> GetExported(object? data, CommandTypes commandTypes) {
        var exported = new List<string>();

        switch (data) {
            case object[] strings:
                exported.AddRange(strings.Cast<string>());
                break;
            case string starString when starString == "*":
                var sessionState = InitialSessionState.CreateDefault();
                if (GetExportedModule(this).IsErr(out var exportError, out var exportPath)) {
                    Logger.Error($"Unable to export module {this.ModuleSpec.Name}: {exportError.Message}");
                    return exported;
                }
                sessionState.ImportPSModulesFromPath(exportPath);

                // Also ensure all dependencies are loaded
                foreach (var dependency in this.GetDownstreamModules()) {
                    if (GetExportedModule(dependency).IsErr(out exportError, out var dependencyExportPath)) {
                        Logger.Error($"Unable to export dependency {dependency.ModuleSpec.Name}: {exportError.Message}");
                        return exported;
                    }
                    sessionState.ImportPSModulesFromPath(dependencyExportPath);
                }

                PowerShell pwsh;
                try {
                    pwsh = PowerShell.Create(sessionState);
                } catch (Exception err) {
                    Logger.Error($"Unable to create PowerShell session state: {err.Message}");
                    Program.Errors.Add(err);
                    return exported;
                }

                exported.AddRange(pwsh.Runspace.SessionStateProxy.InvokeCommand
                    .GetCommands("*", commandTypes, true)
                    .Where(command => command.ModuleName == this.ModuleSpec.Name)
                    .Select(command => command.Name));
                break;
            case string str:
                exported.Add(str);
                break;
            case null:
                break;
            default:
                throw new InvalidDataException($"{commandTypes}sToExport must be a string or an array of strings, but was {data.GetType()}");
        }

        var extraExports = commandTypes switch {
            CommandTypes.Function => this.ThisExtraModuleInfo.Value.FunctionsToExport,
            CommandTypes.Cmdlet => this.ThisExtraModuleInfo.Value.CmdletsToExport,
            CommandTypes.Alias => this.ThisExtraModuleInfo.Value.AliasesToExport,
            CommandTypes.Filter => throw new NotImplementedException(),
            CommandTypes.ExternalScript => throw new NotImplementedException(),
            CommandTypes.Application => throw new NotImplementedException(),
            CommandTypes.Script => throw new NotImplementedException(),
            CommandTypes.Configuration => throw new NotImplementedException(),
            CommandTypes.All => throw new NotImplementedException(),
            _ => throw new ArgumentOutOfRangeException(nameof(commandTypes), commandTypes, null)
        };
        if (extraExports != null) exported.AddRange(extraExports);

        return exported;
    }

    public override IEnumerable<string> GetExportedFunctions() {
        var manifest = this.GetPowerShellManifest();

        var exportedFunctions = new List<string>();
        var functionsToExport = this.GetExported(manifest["FunctionsToExport"], CommandTypes.Function);
        var cmdletsToExport = this.GetExported(manifest["CmdletsToExport"], CommandTypes.Cmdlet);
        var aliasesToExport = this.GetExported(manifest["AliasesToExport"], CommandTypes.Alias);

        exportedFunctions.AddRange(functionsToExport);
        exportedFunctions.AddRange(cmdletsToExport);
        exportedFunctions.AddRange(aliasesToExport);

        return exportedFunctions;
    }

    private Fin<ZipArchive> GetZipArchive() {
        if (this.ZipArchive != null) return this.ZipArchive;
        if (this.GetContentBytes().IsErr(out var error, out var bytes)) return error;

        try {
            return this.ZipArchive = new ZipArchive(new MemoryStream((byte[])bytes.Clone()), ZipArchiveMode.Read, false);
        } catch (Exception err) {
            return LanguageExt.Common.Error.New(err.Message);
        }
    }

    private Hashtable GetPowerShellManifest() {
        if (this.PowerShellManifest != null) return this.PowerShellManifest;

        if (this.GetZipArchive().IsErr(out var archiveError, out var archive)) {
            Logger.Error($"Unable to open archive for {this.ModuleSpec.Name}: {archiveError.Message}");
            return this.PowerShellManifest = [];
        }
        ZipArchiveEntry? psd1Entry;
        try {
            psd1Entry = archive.GetEntry($"{this.ModuleSpec.Name}.psd1");
        } catch (InvalidDataException err) {
            Logger.Error($"Unable to open entry for {this.ModuleSpec.Name} to find the PSD1 file: {err.Message}");
            return this.PowerShellManifest = [];
        }

        if (psd1Entry == null) {
            this.PowerShellManifest = [];
            return this.PowerShellManifest;
        }

        using var psd1Stream = psd1Entry.Open();
        using var psd1Reader = new StreamReader(psd1Stream);
        var psd1String = psd1Reader.ReadToEnd();

        return Program.RunPowerShell(psd1String)
            .Map(objects => (Hashtable)objects[0].BaseObject)
            .Match(
                Succ: psd1 => this.PowerShellManifest = psd1,
                Fail: err => {
                    Logger.Debug($"Failed to parse the PSD1 file for module {this.ModuleSpec.Name}, assuming no requirements.");
                    return this.PowerShellManifest = [];
                }
            );
    }

    private static Fin<string> GetExportedModule(Compiled module) {
        if (module.GetNameHash().IsErr(out var nameHashError, out var nameHash)) {
            return nameHashError;
        }

        var version = module.Version.ToString();
        var tempModuleRootPath = Path.Combine(Path.GetTempPath(), $"PowerShellGet\\_Export_{nameHash}");
        var tempOutput = Path.Combine(tempModuleRootPath, module.ModuleSpec.Name, version);
        if (!Directory.Exists(tempOutput)) {
            Directory.CreateDirectory(tempOutput);

            if (module is CompiledRemoteModule remoteModule) {
                if (remoteModule.GetZipArchive().IsErr(out var archiveError, out var archive)) {
                    return archiveError;
                }

                archive.ExtractToDirectory(tempOutput);

            } else if (module is CompiledLocalModule localModule) {
                var lines = localModule.Document.GetLines();
                using var stream = new FileStream(Path.Combine(tempOutput, $"{module.ModuleSpec.Name}.psm1"), FileMode.Create);
                using var writer = new StreamWriter(stream);
                foreach (var line in lines) {
                    writer.WriteLine(line.ToString());
                }
            }
        }

        Logger.Debug($"Exported module path: {tempOutput}");
        return tempOutput;
    }

    private void UpdateArchiveContents() {
        if (this.UpdatedContentBytes.IsSome) return;

        lock (this.UpdatingArchiveLock) {
            if (this.UpdatedContentBytes.IsSome) return; // Double-check after acquiring the lock

            Logger.Debug($"Updating archive contents for {this.ModuleSpec.Name}.");

            if (this.GetZipArchive().IsErr(out var archiveError, out var originalArchive)) {
                Logger.Error($"Failed to open archive for {this.ModuleSpec.Name}: {archiveError.Message}");
                return;
            }

            var uniqueModuleName = $"{this.ModuleSpec.Name}_{Guid.NewGuid():N}";

            var expandedPath = Path.Join(RewritingFolder, uniqueModuleName);
            if (Directory.Exists(expandedPath)) Directory.Delete(expandedPath, true);
            Directory.CreateDirectory(expandedPath);
            originalArchive.ExtractToDirectory(expandedPath, true);

            this.RewriteRequiredModules(expandedPath);
            this.MoveModuleManifest(expandedPath);

            var tempArchivePath = Path.Join(RewritingFolder, $"{uniqueModuleName}.nupkg");
            if (File.Exists(tempArchivePath)) File.Delete(tempArchivePath);
            ZipFile.CreateFromDirectory(expandedPath, tempArchivePath);

            this.UpdatedContentBytes = File.ReadAllBytes(tempArchivePath);
            this.ZipArchive = null;
            this.SetContentBytes(new Lazy<Fin<byte[]>>(() => this.UpdatedContentBytes.Unwrap()));
            Directory.Delete(expandedPath, true);
            File.Delete(tempArchivePath);
        }
    }

    private void RewriteRequiredModules(string expandedRoot) {
        var manifest = this.GetPowerShellManifest();
        if (manifest["RequiredModules"] is object[] requiredModulesArray) {
            var mappedRequiredModules = new List<Hashtable>(requiredModulesArray.Length);
            foreach (var moduleObject in requiredModulesArray) {
                var moduleName = string.Empty;
                Guid? guid = null;
                Version? minimumVersion = null;
                Version? maximumVersion = null;
                Version? requiredVersion = null;
                if (moduleObject is string) {
                    moduleName = moduleObject.ToString()!;
                } else if (moduleObject is Hashtable moduleTable) {
                    moduleName = moduleTable["ModuleName"]!.ToString()!;
                    _ = Version.TryParse((string?)moduleTable["ModuleVersion"], out minimumVersion);
                    _ = Version.TryParse((string?)moduleTable["MaximumVersion"], out maximumVersion);
                    _ = Version.TryParse((string?)moduleTable["RequiredVersion"], out requiredVersion);
                    _ = Guid.TryParse((string?)moduleTable["GUID"], out var guidNonNull);
                    guid = guidNonNull;
                }

                var moduleInstance = new ModuleSpec(moduleName, guid, minimumVersion, maximumVersion, requiredVersion);
                Logger.Debug($"Resolving required module {moduleName} with guid {guid} and versions: min={minimumVersion}, max={maximumVersion}, required={requiredVersion}");
                var found = this.ResolvableParent.FindResolvable(moduleInstance);
                if (found.IsNone) {
                    Logger.Warn($"Required module {moduleName} not found in the current session, skipping; This may be an issue.");
                } else {
                    var moduleMatch = found.Unwrap();
                    moduleMatch.Deconstruct(out var module, out var match);
                    Logger.Debug($"Found required module; Match type: {match}");
                    if (match == ModuleMatch.Incompatible) {
                        Logger.Warn($"Required module {moduleName} is incompatible with the compiled instance, this will probably cause issues.");
                    }
                    var compiledModule = this.GetCompiledFromResolvable(module).Unwrap();

                    if (compiledModule.GetNameHash().IsErr(out var nameHashError, out var compiledNameHash)) {
                        Logger.Error($"Failed to get name hash for {compiledModule.ModuleSpec.Name}: {nameHashError.Message}");
                        continue;
                    }

                    var newModuleTable = new Hashtable {
                        ["ModuleName"] = compiledNameHash,
                        ["GUID"] = compiledModule.ModuleSpec.Id?.ToString(),
                        ["ModuleVersion"] = module.ModuleSpec.MinimumVersion?.ToString(),
                        ["RequiredVersion"] = module.ModuleSpec.RequiredVersion?.ToString(),
                        ["MaximumVersion"] = module.ModuleSpec.MaximumVersion?.ToString()
                    };

                    var tableKeyEnumerator = newModuleTable.Clone().Cast<Hashtable>().Keys.GetEnumerator();
                    while (tableKeyEnumerator.MoveNext()) {
                        var key = tableKeyEnumerator.Current;
                        if (newModuleTable[key] == null) {
                            newModuleTable.Remove(key);
                        }
                    }

                    mappedRequiredModules.Add(newModuleTable);
                }
            }

            manifest["RequiredModules"] = mappedRequiredModules.ToArray();

            var outputPath = Path.Join(expandedRoot, $"{this.ModuleSpec.Name}.psd1");
            var serialized = Psd1Serializer.Serialize(manifest);
            File.WriteAllText(outputPath, serialized);
            Logger.Debug($"Wrote updated manifest to {outputPath}");
        }
    }

    public void Dispose() {
        this.ZipArchive?.Dispose();
        this.ZipArchive = null;
        GC.SuppressFinalize(this);
    }

    private void MoveModuleManifest(string expandedRoot) {

        var manifestPath = Path.Join(expandedRoot, $"{this.ModuleSpec.Name}.psd1");
        if (File.Exists(manifestPath)) {
            if (this.GetNameHash().IsErr(out var nameHashError, out var nameHash)) {
                Logger.Error($"Failed to get name hash for {this.ModuleSpec.Name}: {nameHashError.Message}");
                return;
            }

            var newManifestPath = Path.Join(expandedRoot, $"{nameHash}.psd1");
            File.Move(manifestPath, newManifestPath);
        } else {
            Logger.Trace($"Module manifest {manifestPath} does not exist, skipping move.");
        }
    }
}
