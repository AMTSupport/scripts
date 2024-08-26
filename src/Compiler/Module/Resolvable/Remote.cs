// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.IO.Compression;
using System.Management.Automation;
using Compiler.Module.Compiled;
using Compiler.Requirements;
using NLog;

namespace Compiler.Module.Resolvable;

public class ResolvableRemoteModule : Resolvable {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    private MemoryStream? MemoryStream;
    private string? CachedFile;

    public ResolvableRemoteModule(ModuleSpec moduleSpec) : base(moduleSpec) => this.QueueResolve();

    private string CachePath => Path.Join(
        Path.GetTempPath(),
        "PowerShellGet",
        this.ModuleSpec.Name
    );

    public override ModuleMatch GetModuleMatchFor(ModuleSpec requirement) => ModuleSpec.CompareTo(requirement);

    public override void ResolveRequirements()
    {
        lock (Requirements)
        {
            var memoryStream = _memoryStream ??= new MemoryStream(File.ReadAllBytes(FindCachedResult() ?? CacheResult()), false);
            using var archive = new ZipArchive(memoryStream, ZipArchiveMode.Read, true);
            var psd1Entry = archive.GetEntry($"{ModuleSpec.Name}.psd1");
            if (psd1Entry == null)
            {
                Logger.Debug($"Failed to find the PSD1 file for module {ModuleSpec.Name}, assuming no requirements.");
                return;
            }

            // Read the PSD1 file and parse it as a hashtable.
            using var psd1Stream = psd1Entry.Open();
            if (PowerShell.Create().AddScript(new StreamReader(psd1Stream).ReadToEnd()).Invoke()[0].BaseObject is not Hashtable psd1)
            {
                Logger.Debug($"Failed to parse the PSD1 file for module {ModuleSpec.Name}, assuming no requirements.");
                return;
            }

            if (psd1["PowerShellVersion"] is string psVersion) Requirements.AddRequirement(new PSVersionRequirement(Version.Parse(psVersion)));
            if (psd1["RequiredModules"] is object[] requiredModules)
            {
                foreach (var requiredModule in requiredModules.Cast<Hashtable>())
                {
                    var moduleName = requiredModule["ModuleName"]!.ToString();
                    _ = Version.TryParse((string?)requiredModule["ModuleVersion"], out var minimumVersion);
                    _ = Version.TryParse((string?)requiredModule["MaximumVersion"], out var maximumVersion);
                    _ = Version.TryParse((string?)requiredModule["RequiredVersion"], out var requiredVersion);
                    _ = Guid.TryParse((string?)requiredModule["Guid"], out var guid);

                    var requiredModuleSpec = new ModuleSpec(moduleName!, guid, minimumVersion, maximumVersion, requiredVersion);
                    Requirements.AddRequirement(requiredModuleSpec);
                }
            }
        }
    }

    public override Compiled.Compiled IntoCompiled() => new CompiledRemoteModule(
        this.ModuleSpec,
        this.Requirements,
        this.MemoryStream ??= new MemoryStream(File.ReadAllBytes(this.FindCachedResult() ?? this.CacheResult().ThrowIfFail()), false)
    );

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
        }).Select(file => {
            var fileName = Path.GetFileName(file);
            var version = fileName.Substring(this.ModuleSpec.Name.Length + 1, fileName.Length - this.ModuleSpec.Name.Length - 1 - ".nupkg".Length);

            try {
                return new Version(version);
            } catch {
                throw new Exception($"Failed to parse version {version} from file {file}");
            }
        });

        var selectedVersion = versions.Where(version => {
            var otherSpec = new ModuleSpec(this.ModuleSpec.Name, this.ModuleSpec.Id, requiredVersion: version);
            var matchType = otherSpec.CompareTo(this.ModuleSpec);

            return matchType is ModuleMatch.Same or ModuleMatch.Stricter;
        }).OrderByDescending(version => version).FirstOrDefault();

        return selectedVersion == null ? null : this.CachedFile = Path.Join(this.CachePath, $"{this.ModuleSpec.Name}.{selectedVersion}.nupkg");
    }

    public string CacheResult()
    {
        var versionString = ConvertVersionParameters(this.ModuleSpec.RequiredVersion?.ToString(), this.ModuleSpec.MinimumVersion?.ToString(), this.ModuleSpec.MaximumVersion?.ToString());
        var powerShellCode = /*ps1*/ $$"""
        Set-StrictMode -Version 3;

        try {
            $Module = Find-PSResource -Name '{{ModuleSpec.Name}}' {{(versionString != null ? $"-Version '{versionString}'" : "")}};
        } catch {
            exit 10;
        }

        try {
            $Module | Save-PSResource -Path '{{CachePath}}' -AsNupkg -SkipDependencyCheck;
        } catch {
            exit 11;
        }

        return $env:TEMP | Join-Path -ChildPath "PowerShellGet/{{ModuleSpec.Name}}/{{ModuleSpec.Name}}.$($Module.Version).nupkg";
        """;

        Logger.Debug(
            "Running PowerShell code to download module from the PowerShell Gallery."
            + Environment.NewLine
            + powerShellCode
        );

        if (!Directory.Exists(this.CachePath)) {
            Directory.CreateDirectory(this.CachePath);
        }

        var pwsh = PowerShell.Create(RunspaceMode.NewRunspace);
        pwsh.RunspacePool = Program.RunspacePool.Value;
        pwsh.AddScript(PowerShellCode);
        var result = pwsh.Invoke();

        if (pwsh.HadErrors)
        {
            throw new Exception("Failed to download module from the PowerShell Gallery.", pwsh.Streams.Error[0]?.Exception);
        }

        var returnedResult = result.First().ToString();
        Logger.Debug($"Downloaded module {ModuleSpec.Name} from the PowerShell Gallery to {returnedResult}.");
        return returnedResult;
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
