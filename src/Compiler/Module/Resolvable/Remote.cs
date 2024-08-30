// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.IO.Compression;
using System.Security.Cryptography;
using Compiler.Module.Compiled;
using Compiler.Requirements;
using LanguageExt;
using LanguageExt.Traits;
using NLog;
namespace Compiler.Module.Resolvable;

public class ResolvableRemoteModule : Resolvable {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private static readonly object UsingPSRepoLock = new();

    private MemoryStream? MemoryStream;
    private string? CachedFile;

    public ResolvableRemoteModule(ModuleSpec moduleSpec) : base(moduleSpec) => this.QueueResolve();

    private string CachePath => Path.Join(
        Path.GetTempPath(),
        "PowerShellGet",
        this.ModuleSpec.Name
    );

    public override ModuleMatch GetModuleMatchFor(ModuleSpec requirement) => this.ModuleSpec.CompareTo(requirement);

    public override Option<Error> ResolveRequirements() {
        this.MemoryStream ??= new MemoryStream(File.ReadAllBytes(this.FindCachedResult() ?? this.CacheResult().Match(
            Fail: error => throw error,
            Succ: path => path
        )), false);

        return this.MemoryStream.AsOption()
            .Filter(static memoryStream => memoryStream == null || memoryStream.Length != 0)
            .Map(static memoryStream => new ZipArchive(memoryStream, ZipArchiveMode.Read, true))
            .Map(archive => archive.GetEntry($"{this.ModuleSpec.Name}.psd1"))
            .Filter(static entry => entry != null)
            .Select(entry => entry!.Open())
            .Filter(static stream => stream != null)
            .Map(static stream => new StreamReader(stream!))
            .Map(static reader => reader.ReadToEnd())
            .Filter(static psd1String => !string.IsNullOrWhiteSpace(psd1String))
            .ToFin()
            .Bind(psd1String => Program.RunPowerShell(psd1String))
            .Map(static objects => (Hashtable)objects.First().BaseObject)
            .Match(
                Fail: static error => Some(error),
                Succ: psd1 => {
                    if (psd1["PowerShellVersion"] is string psVersion)
                        this.Requirements.AddRequirement(new PSVersionRequirement(Version.Parse(psVersion)));
                    if (psd1["RequiredModules"] is object[] requiredModules) {
                        foreach (var requiredModule in requiredModules.Cast<Hashtable>()) {
                            var moduleName = requiredModule["ModuleName"]!.ToString();
                            _ = Version.TryParse((string?)requiredModule["ModuleVersion"], out var minimumVersion);
                            _ = Version.TryParse((string?)requiredModule["MaximumVersion"], out var maximumVersion);
                            _ = Version.TryParse((string?)requiredModule["RequiredVersion"], out var requiredVersion);
                            _ = Guid.TryParse((string?)requiredModule["Guid"], out var guid);

                            var requiredModuleSpec = new ModuleSpec(moduleName!, guid, minimumVersion, maximumVersion, requiredVersion);
                            this.Requirements.AddRequirement(requiredModuleSpec);
                        }
                    }

                    return None;
                }
            );
    }

    public override Fin<Compiled.Compiled> IntoCompiled() {
        if (this.MemoryStream == null) {
            var memoryStreamResult = this.FindCachedResult().AsOption().ToFin()
                .BiBind(
                    Succ: value => FinSucc(value),
                    Fail: _ => this.CacheResult().Catch(err => err.Enrich(this.ModuleSpec)).As())
                .AndThen(File.ReadAllBytes)
                .AndThen(bytes => new MemoryStream([.. bytes], false));

            if (memoryStreamResult.IsErr(out var error, out _)) return error;
            this.MemoryStream = memoryStreamResult.Unwrap();
        }

        return new CompiledRemoteModule(
            this.ModuleSpec,
            this.Requirements,
            this.MemoryStream
        );
    }

    public override bool Equals(object? obj) {
        if (obj is null) return false;
        if (ReferenceEquals(this, obj)) return true;
        return obj is ResolvableRemoteModule other &&
               this.ModuleSpec.CompareTo(other.ModuleSpec) == ModuleMatch.Same;
    }

    public string? FindCachedResult() {
        if (this.CachedFile != null) return this.CachedFile;

        if (!Directory.Exists(this.CachePath)) return null;

        var files = Directory.GetFiles(this.CachePath, "*.nupkg");
        if (files.Length == 0) return null;

        var versions = files.Where(file => {
            var fileName = Path.GetFileName(file);
            return fileName.StartsWith(this.ModuleSpec.Name, StringComparison.OrdinalIgnoreCase);
        }).Bind(file => {
            var fileName = Path.GetFileName(file);
            var version = fileName.Substring(this.ModuleSpec.Name.Length + 1, fileName.Length - this.ModuleSpec.Name.Length - 1 - ".nupkg".Length);

            try {
                return Some(new Version(version));
            } catch {
                return Option<Version>.None; // Ignore invalid versions.
            }
        });

        var selectedVersion = versions.Where(version => {
            var otherSpec = new ModuleSpec(this.ModuleSpec.Name, this.ModuleSpec.Id, requiredVersion: version);
            var matchType = otherSpec.CompareTo(this.ModuleSpec);

            return matchType is ModuleMatch.Same or ModuleMatch.Stricter;
        }).OrderByDescending(version => version).FirstOrDefault();

        return selectedVersion == null ? null : this.CachedFile = Path.Join(this.CachePath, $"{this.ModuleSpec.Name}.{selectedVersion}.nupkg");
    }

    public Fin<string> CacheResult() {
        var versionString = ConvertVersionParameters(this.ModuleSpec.RequiredVersion?.ToString(), this.ModuleSpec.MinimumVersion?.ToString(), this.ModuleSpec.MaximumVersion?.ToString());
        var powerShellCode = /*ps1*/ $$"""
        Set-StrictMode -Version 3;

        Set-PSResourceRepository -Name PSGallery -Trusted -Confirm:$False;

        $Module = Find-PSResource -Name '{{this.ModuleSpec.Name}}' {{(versionString != null ? $"-Version '{versionString}'" : "")}};
        $Module | Save-PSResource -Path '{{this.CachePath}}' -AsNupkg -SkipDependencyCheck;

        return "$env:TEMP/PowerShellGet/{{this.ModuleSpec.Name}}/{{this.ModuleSpec.Name}}.$($Module.Version).nupkg";
        """;

        Logger.Debug(
            "Running PowerShell code to download module from the PowerShell Gallery."
            + Environment.NewLine
            + powerShellCode
        );

        if (!Directory.Exists(this.CachePath)) {
            Directory.CreateDirectory(this.CachePath);
        }

        // Only one process can download a module at a time.
        lock (UsingPSRepoLock) {
            return Program.RunPowerShell(powerShellCode)
                .Map(objects => objects.First().ToString())
                .Tap(path => this.CachedFile = path);
        }
    }

    // Based on https://github.com/PowerShell/PowerShellGet/blob/c6aea39ea05491c648efd7aebdefab1ae7c5b213/src/PowerShellGet.psm1#L111-L144
    private static string? ConvertVersionParameters(
        string? requiredVersion,
        string? minimumVersion,
        string? maximumVersion) => (requiredVersion, minimumVersion, maximumVersion) switch {
            (null, null, null) => null,
            (string ver, null, null) => ver,
            (_, string min, null) => $"[{min},)",
            (_, null, string max) => $"(,{max}]",
            (_, string min, string max) => $"[{min},{max}]"
        };

    public override int GetHashCode() => this.ModuleSpec.GetHashCode();
}
