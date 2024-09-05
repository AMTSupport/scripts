// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.Diagnostics.Contracts;
using System.IO.Compression;
using Compiler.Module.Compiled;
using Compiler.Requirements;
using LanguageExt;
using LanguageExt.Traits;
using NLog;
namespace Compiler.Module.Resolvable;

public class ResolvableRemoteModule(ModuleSpec moduleSpec) : Resolvable(moduleSpec), IDisposable {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private static readonly object UsingPSRepoLock = new();
    private MemoryStream? MemoryStream;

    // Only public for testing purposes.
    public Atom<Either<string, ManualResetEventSlim>>? CachedFile;

    public string CachePath => Path.Join(
        Path.GetTempPath(),
        "PowerShellGet",
        this.ModuleSpec.Name
    );

    ~ResolvableRemoteModule() {
        this.MemoryStream?.Dispose();
    }

    [Pure]
    public override ModuleMatch GetModuleMatchFor(ModuleSpec requirement) => this.ModuleSpec.CompareTo(requirement);

    public override async Task<Option<Error>> ResolveRequirements() {
        this.MemoryStream ??= new MemoryStream(File.ReadAllBytes((await this.FindCachedResult()).ToFin().BindFail(_ => this.CacheResult()).Match(
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

    public override async Task<Fin<Compiled.Compiled>> IntoCompiled() {
        if (this.MemoryStream == null) {
            var memoryStreamResult = (await this.FindCachedResult()).ToFin()
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

    [Pure]
    public override bool Equals(object? obj) {
        if (obj is null) return false;
        if (ReferenceEquals(this, obj)) return true;
        return obj is ResolvableRemoteModule other && this.GetModuleMatchFor(other.ModuleSpec) == ModuleMatch.Same;
    }

    public async Task<Option<string>> FindCachedResult() {
        if (this.CachedFile is not null) {
            var either = this.CachedFile.Value;
            if (either.IsLeft) return (string)either;

            var waitingForResetEvent = (ManualResetEventSlim)either;
            await waitingForResetEvent.WaitHandle.WaitOneAsync(500, Program.CancelSource.Token);
            await Task.Delay(10); // I don't know why this is needed, but it is.
            if (waitingForResetEvent.IsSet) return (string)this.CachedFile.Value;
        } else {
            this.CachedFile = Atom<Either<string, ManualResetEventSlim>>(new ManualResetEventSlim(false));
        }

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
        var resetEvent = (ManualResetEventSlim)this.CachedFile.Value;
        this.CachedFile.Swap(_ => Left(selectedFile));
        resetEvent.Set();

        return selectedFile;
    }

    public Fin<string> CacheResult() {
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
                        this.CachedFile = Atom<Either<string, ManualResetEventSlim>>(Left(path));
                    } else {
                        this.CachedFile.Swap(v => {
                            if (v.IsRight) {
                                var resetEvent = (ManualResetEventSlim)v;
                                resetEvent.Set();
                            }

                            return Left(path);
                        });
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

    public void Dispose() {
        this.MemoryStream?.Dispose();
        GC.SuppressFinalize(this);
    }
}
