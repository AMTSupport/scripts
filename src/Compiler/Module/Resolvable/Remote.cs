// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.Diagnostics.Contracts;
using System.IO.Compression;
using Compiler.Module.Compiled;
using Compiler.Requirements;
using LanguageExt;
using NLog;
namespace Compiler.Module.Resolvable;

public class ResolvableRemoteModule(ModuleSpec moduleSpec) : Resolvable(moduleSpec) {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private static readonly object UsingPSRepoLock = new();
    private byte[]? Bytes;

    // Only public for testing purposes.
    public Atom<Either<Option<string>, Task<Option<string>>>>? CachedFile;

    public string CachePath => Path.Join(
        Path.GetTempPath(),
        "PowerShellGet",
        this.ModuleSpec.Name
    );

    [Pure]
    public override ModuleMatch GetModuleMatchFor(ModuleSpec requirement) => this.ModuleSpec.CompareTo(requirement);

    public override async Task<Option<Error>> ResolveRequirements() {
        if (this.Bytes == null) {
            var cachedResult = await this.GetNupkgPath();
            if (cachedResult.IsErr(out var error, out var nupkgPath)) return Some(error);
            this.Bytes = File.ReadAllBytes(nupkgPath);
        }

        return this.Bytes.AsOption()
            .Filter(static bytes => bytes == null || bytes.Length != 0)
            .Map(static bytes => new ZipArchive(new MemoryStream(bytes), ZipArchiveMode.Read, false))
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

    public override async Task<Fin<Compiled.Compiled>> IntoCompiled() {
        if (this.Bytes == null) {
            var bytesResult = (await this.GetNupkgPath())
                .BindFail(err => err.Enrich(this.ModuleSpec))
                .AndThen(File.ReadAllBytes);

            if (bytesResult.IsErr(out var error, out this.Bytes)) return error;
        }

        return new CompiledRemoteModule(
            this.ModuleSpec,
            this.Requirements,
            this.Bytes
        );
    }

    [Pure]
    public override bool Equals(object? obj) {
        if (obj is null) return false;
        if (ReferenceEquals(this, obj)) return true;
        return obj is ResolvableRemoteModule other && this.GetModuleMatchFor(other.ModuleSpec) == ModuleMatch.Same;
    }

    public async Task<Fin<string>> GetNupkgPath() {
        var cachedResult = await this.FindCachedResult();
        if (cachedResult.IsSome(out var path)) return path;

        return (await this.CacheResult()).BindFail(err => err.Enrich(this.ModuleSpec));
    }

    public async Task<Option<string>> FindCachedResult() {
        if (this.CachedFile is not null) {
            var either = this.CachedFile.Value;
            if (either.IsLeft) return (Option<string>)either;

            var runningTask = (Task<Option<string>>)either;
            return await runningTask;
        }

        var task = Task.Run<Option<string>>(() => {
            if (!Directory.Exists(this.CachePath)) return None;

            var files = Directory.GetFiles(this.CachePath, "*.nupkg");
            if (files.Length == 0) return None;

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

            Func<Version, bool> findBestVersionFunc = (this.ModuleSpec.RequiredVersion, this.ModuleSpec.MinimumVersion, this.ModuleSpec.MaximumVersion) switch {
                (Version requiredVersion, _, _) => version => version == requiredVersion,
                (_, Version minimumVersion, Version maximumVersion) => version => version >= minimumVersion && version <= maximumVersion,
                (_, Version minimumVersion, null) => version => version >= minimumVersion,
                (_, null, Version maximumVersion) => version => version <= maximumVersion,
                (null, null, null) => (_) => true
            };

            var posibleVersions = versions.Where(version => findBestVersionFunc(version)).ToArray();
            var selectedVersion = posibleVersions.OrderByDescending(version => version).FirstOrDefault();
            if (selectedVersion == null) return None;

            var selectedFile = Path.Join(this.CachePath, $"{this.ModuleSpec.Name}.{selectedVersion}.nupkg");

            return selectedFile;
        });

        this.CachedFile = Atom(Either<Option<string>, Task<Option<string>>>.Right(task));
        var result = await task;
        this.CachedFile.Swap(_ => Left(result));
        return result;
    }

    public async Task<Fin<string>> CacheResult() {
        if (this.CachedFile is not null) {
            var either = this.CachedFile.Value;
            if (either.IsLeft && ((Option<string>)either).IsSome(out var path)) {
                return path;
            } else if (either.IsRight) {
                var runningTask = (Task<Option<string>>)either;
                if ((await runningTask).IsSome(out path)) {
                    return path;
                }
            }
        }

        var versionString = ConvertVersionParameters(this.ModuleSpec.RequiredVersion?.ToString(), this.ModuleSpec.MinimumVersion?.ToString(), this.ModuleSpec.MaximumVersion?.ToString());
        var powerShellCode = /*ps1*/ $$"""
        Set-StrictMode -Version 3;

        Set-PSResourceRepository -Name PSGallery -Trusted -Confirm:$False;

        $Module = Find-PSResource -Name '{{this.ModuleSpec.Name}}' {{(versionString != null ? $"-Version '{versionString}'" : "")}};
        $Module | Save-PSResource -Path '{{this.CachePath}}' -AsNupkg -SkipDependencyCheck;

        return "{{this.CachePath}}/{{this.ModuleSpec.Name}}.$($Module.Version).nupkg";
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
                .Tap(path => {
                    if (this.CachedFile is null) {
                        this.CachedFile = Atom<Either<Option<string>, Task<Option<string>>>>(Left(Some(path)));
                    } else {
                        this.CachedFile.Swap(_ => Left(Some(path)));
                    }
                });
        }
    }

    // Based on https://github.com/PowerShell/PowerShellGet/blob/c6aea39ea05491c648efd7aebdefab1ae7c5b213/src/PowerShellGet.psm1#L111-L144
    [Pure]
    public static string? ConvertVersionParameters(
        string? requiredVersion,
        string? minimumVersion,
        string? maximumVersion) => (requiredVersion, minimumVersion, maximumVersion) switch {
            (null, null, null) => null,
            (string ver, _, _) => ver,
            (_, string min, null) => $"[{min},)",
            (_, null, string max) => $"(,{max}]",
            (_, string min, string max) => $"[{min},{max}]"
        };

    [Pure]
    public override int GetHashCode() => this.ModuleSpec.GetHashCode();
}
