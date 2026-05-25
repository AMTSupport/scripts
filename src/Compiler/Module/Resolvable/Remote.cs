// Copyright (c) 2024, 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections;
using System.Diagnostics.Contracts;
using System.IO.Compression;

using System.Net;
using System.Text.RegularExpressions;
using Compiler.Module.Compiled;

using Compiler.Requirements;
using LanguageExt;
using NLog;

namespace Compiler.Module.Resolvable;

public partial class ResolvableRemoteModule(ModuleSpec moduleSpec) : Resolvable(moduleSpec) {

    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private static readonly Lock UsingPSRepoLock = new();
    private static readonly HttpClient HttpClient = new() {
        Timeout = TimeSpan.FromMinutes(2)
    };
    private byte[]? Bytes;

    // Only public for testing purposes.
    // Cached value or running task for resolving cached file path.
    public Option<string>? CachedFile;
    public Task<Option<string>>? CachedFileTask;

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
                            _ = Guid.TryParse((string?)requiredModule["GUID"], out var guid);
                            Guid? actualGuid = guid == Guid.Empty ? null : guid;

                            var requiredModuleSpec = new ModuleSpec(moduleName!, actualGuid, minimumVersion, maximumVersion, requiredVersion);
                            this.Requirements.AddRequirement(requiredModuleSpec);
                        }
                    }

                    return None;
                }
            );
    }

    public override async Task<Fin<Compiled.Compiled>> IntoCompiled(ResolvableParent resolvableParent) {
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
        ) {
            ResolvableParent = resolvableParent
        };
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
        if (this.CachedFile is { } cachedFile) {
            return cachedFile;
        }

        if (this.CachedFileTask is { } runningTask) {
            return await runningTask;
        }

        var task = Task.Run<Option<string>>(() => {
            if (!Directory.Exists(this.CachePath)) return None;

            var files = Directory.GetFiles(this.CachePath, "*.nupkg");
            if (files.Length == 0) return None;

            var versions = files.Where(file => {
                var fileName = Path.GetFileName(file);
                return fileName.StartsWith(this.ModuleSpec.Name, StringComparison.OrdinalIgnoreCase);
            }).Select(file => {
                var fileName = Path.GetFileName(file);
                var version = fileName[(this.ModuleSpec.Name.Length + 1)..^".nupkg".Length];

                try {
                    return new Version(version);
                } catch {
                    return null;
                }
            }).Where(version => version != null).Cast<Version>();

            Func<Version, bool> findBestVersionFunc = (this.ModuleSpec.RequiredVersion, this.ModuleSpec.MinimumVersion, this.ModuleSpec.MaximumVersion) switch {
                (Version requiredVersion, _, _) => version => version == requiredVersion,
                (_, Version minimumVersion, Version maximumVersion) => version => version >= minimumVersion && version <= maximumVersion,
                (_, Version minimumVersion, null) => version => version >= minimumVersion,
                (_, null, Version maximumVersion) => version => version <= maximumVersion,
                (null, null, null) => (_) => true
            };

            var possibleVersions = versions.Where(version => findBestVersionFunc(version)).ToArray();
            var selectedVersion = possibleVersions.OrderByDescending(version => version).FirstOrDefault();
            if (selectedVersion == null) return None;

            var selectedFile = Path.Join(this.CachePath, $"{this.ModuleSpec.Name}.{selectedVersion}.nupkg");

            return selectedFile;
        });

        this.CachedFileTask = task;
        var result = await task;
        this.CachedFileTask = null;
        this.CachedFile = result;
        return result;
    }

    public async Task<Fin<string>> CacheResult() {
        if (this.CachedFile is { } cachedFile && cachedFile.IsSome(out var path)) {
            return path;
        }

        if (this.CachedFileTask is { } runningTask) {
            var runningResult = await runningTask;
            if (runningResult.IsSome(out path)) {
                return path;
            }
        }

        if (!Directory.Exists(this.CachePath)) {
            Directory.CreateDirectory(this.CachePath);
        }

        var httpResult = await this.CacheResultWithHttp();
        if (httpResult.IsSucc) {
            return httpResult;
        }

        if (httpResult.IsErr(out var httpError, out _)) {
            Logger.Warn($"Direct PSGallery download failed for {this.ModuleSpec.Name}, falling back to PowerShell bootstrap: {httpError.Message}");
        }

        return this.TryCacheResultWithPowerShell().BindFail(err => err.Enrich(this.ModuleSpec));
    }

    private Fin<string> TryCacheResultWithPowerShell() {
        var versionString = ConvertVersionParameters(this.ModuleSpec.RequiredVersion?.ToString(), this.ModuleSpec.MinimumVersion?.ToString(), this.ModuleSpec.MaximumVersion?.ToString());
        var powerShellCode = /*ps1*/ $$"""
        $ErrorActionPreference = "Stop";
        Set-StrictMode -Version 3;

        # Some environments do not have PowerShellGet / PackageManagement cmdlets available.
        $HasModule = Get-Module -Name Microsoft.PowerShell.PSResourceGet -ListAvailable;
        if ($HasModule -eq $null) {
            throw "Microsoft.PowerShell.PSResourceGet module is required to download remote dependencies. Install it in pwsh before running compiler.";
        }
        Import-Module -Name Microsoft.PowerShell.PSResourceGet -Force;

        if (Get-Command -Name Set-PSResourceRepository -ErrorAction SilentlyContinue) {
            Set-PSResourceRepository -Name PSGallery -Trusted -Confirm:$False;
        }

        $Module = Find-PSResource -Name '{{this.ModuleSpec.Name}}' {{(versionString != null ? $"-Version '{versionString}'" : "")}};
        $Module | Select-Object -First 1 | Save-PSResource -Path '{{this.CachePath}}' -AsNupkg -SkipDependencyCheck;

        return "{{this.CachePath}}/{{this.ModuleSpec.Name}}.$($Module.Version).nupkg";
        """;

        Logger.Debug(
            "Running PowerShell code to download module from the PowerShell Gallery."
            + Environment.NewLine
            + powerShellCode
        );

        // Only one process can download a module at a time.
        lock (UsingPSRepoLock) {
            return Program.RunPowerShell(powerShellCode)
                .Map(objects => objects.First().ToString())
                .Tap(this.UpdateCachedFile);
        }
    }

    private async Task<Fin<string>> CacheResultWithHttp() {
        var versionResult = await this.ResolveVersionWithHttp();
        if (versionResult.IsErr(out var versionError, out var version)) return versionError;

        var packageUrl = new Uri($"https://www.powershellgallery.com/api/v2/package/{Uri.EscapeDataString(this.ModuleSpec.Name)}/{version}");
        var outputPath = Path.Join(this.CachePath, $"{this.ModuleSpec.Name}.{version}.nupkg");

        lock (UsingPSRepoLock) {
            if (File.Exists(outputPath)) {
                this.UpdateCachedFile(outputPath);
                return outputPath;
            }
        }

        try {
            using var response = await HttpClient.GetAsync(packageUrl, HttpCompletionOption.ResponseHeadersRead);
            if (response.StatusCode == HttpStatusCode.NotFound) {
                return Error.New($"Module {this.ModuleSpec.Name} version {version} was not found in PSGallery.");
            }

            response.EnsureSuccessStatusCode();
            await using var responseStream = await response.Content.ReadAsStreamAsync();
            await using var fileStream = new FileStream(outputPath, FileMode.Create, FileAccess.Write, FileShare.None);
            await responseStream.CopyToAsync(fileStream);
            await fileStream.FlushAsync();
            this.UpdateCachedFile(outputPath);
            return outputPath;
        } catch (Exception err) {
            return Error.New($"Failed to download module {this.ModuleSpec.Name} version {version} from PSGallery: {err.Message}");
        }
    }

    private async Task<Fin<string>> ResolveVersionWithHttp() {
        var feedUrl = new Uri($"https://www.powershellgallery.com/api/v2/FindPackagesById()?id='{Uri.EscapeDataString(this.ModuleSpec.Name)}'");

        try {
            using var response = await HttpClient.GetAsync(feedUrl, HttpCompletionOption.ResponseHeadersRead);
            if (response.StatusCode == HttpStatusCode.NotFound) {
                return Error.New($"Module {this.ModuleSpec.Name} was not found in PSGallery.");
            }

            response.EnsureSuccessStatusCode();
            var feed = await response.Content.ReadAsStringAsync();
            var versions = VersionRegex().Matches(feed)
                .Select(match => match.Groups[1].Value)

                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Select(versionString => Version.TryParse(versionString, out var parsedVersion) ? parsedVersion : null)
                .Where(version => version != null)
                .Cast<Version>()
                .ToArray();

            var selectedVersion = this.SelectBestVersion(versions);
            return selectedVersion == null
                ? Error.New($"No PSGallery version matched constraints for {this.ModuleSpec.Name}.")
                : selectedVersion.ToString();
        } catch (Exception err) {
            return Error.New($"Failed to query PSGallery for module {this.ModuleSpec.Name}: {err.Message}");
        }
    }

    [GeneratedRegex("<d:Version>([^<]+)</d:Version>", RegexOptions.IgnoreCase)]
    private static partial Regex VersionRegex();

    internal Version? SelectBestVersion(IEnumerable<Version> versions) {

        Func<Version, bool> findBestVersionFunc = (this.ModuleSpec.RequiredVersion, this.ModuleSpec.MinimumVersion, this.ModuleSpec.MaximumVersion) switch {
            (Version requiredVersion, _, _) => version => version == requiredVersion,
            (_, Version minimumVersion, Version maximumVersion) => version => version >= minimumVersion && version <= maximumVersion,
            (_, Version minimumVersion, null) => version => version >= minimumVersion,
            (_, null, Version maximumVersion) => version => version <= maximumVersion,
            (null, null, null) => (_) => true
        };

        return versions
            .Where(findBestVersionFunc)
            .OrderByDescending(version => version)
            .FirstOrDefault();
    }

    private void UpdateCachedFile(string path) {
        this.CachedFileTask = null;
        this.CachedFile = Some(path);
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
