using System.Collections;
using System.IO.Compression;
using System.Management.Automation;
using Compiler.Module.Compiled;
using Compiler.Requirements;
using NLog;

namespace Compiler.Module.Resolvable;

public class ResolvableRemoteModule(ModuleSpec moduleSpec) : Resolvable(moduleSpec)
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    private MemoryStream? _memoryStream;
    private string? _cachedFile;

    private string CachePath => Path.Join(
        Path.GetTempPath(),
        "PowerShellGet",
        ModuleSpec.Name
    );

    public override ModuleMatch GetModuleMatchFor(ModuleSpec requirement) => ModuleSpec.CompareTo(requirement);

    public override RequirementGroup ResolveRequirements()
    {
        var requirementGroup = new RequirementGroup();

        var memoryStream = _memoryStream ??= new MemoryStream(File.ReadAllBytes(FindCachedResult() ?? CacheResult()), false);
        using var archive = new ZipArchive(memoryStream, ZipArchiveMode.Read, true);
        var psd1Entry = archive.GetEntry($"{ModuleSpec.Name}.psd1");
        if (psd1Entry == null)
        {
            Logger.Debug($"Failed to find the PSD1 file for module {ModuleSpec.Name}, assuming no requirements.");
            return requirementGroup;
        }

        // Read the PSD1 file and parse it as a hashtable.
        using var psd1Stream = psd1Entry.Open();
        if (PowerShell.Create().AddScript(new StreamReader(psd1Stream).ReadToEnd()).Invoke()[0].BaseObject is not Hashtable psd1)
        {
            Logger.Debug($"Failed to parse the PSD1 file for module {ModuleSpec.Name}, assuming no requirements.");
            return requirementGroup;
        }

        if (psd1["PowerShellVersion"] is string psVersion) requirementGroup.AddRequirement(new PSVersionRequirement(Version.Parse(psVersion)));
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
                requirementGroup.AddRequirement(requiredModuleSpec);
            }
        }


        return requirementGroup;
    }

    public override Compiled.Compiled IntoCompiled() => new CompiledRemoteModule(ModuleSpec)
    {
        MemoryStream = _memoryStream ??= new MemoryStream(File.ReadAllBytes(FindCachedResult() ?? CacheResult()), false),
        Requirements = ResolveRequirements()
    };

    public override bool Equals(object? obj)
    {
        if (obj is null) return false;
        if (ReferenceEquals(this, obj)) return true;
        return obj is ResolvableRemoteModule other &&
               ModuleSpec.CompareTo(other.ModuleSpec) == ModuleMatch.Same;
    }

    public string? FindCachedResult()
    {
        if (_cachedFile != null) return _cachedFile;

        if (!Directory.Exists(CachePath))
        {
            return null;
        }

        var files = Directory.GetFiles(CachePath, "*.nupkg");
        if (files.Length == 0)
        {
            return null;
        }

        var versions = files.Where(file =>
        {
            var fileName = Path.GetFileName(file);
            return fileName.StartsWith(ModuleSpec.Name);
        }).Select(file =>
        {
            var fileName = Path.GetFileName(file);
            var version = fileName.Substring(ModuleSpec.Name.Length + 1, fileName.Length - ModuleSpec.Name.Length - 1 - ".nupkg".Length);

            try { return new Version(version); }
            catch { throw new Exception($"Failed to parse version {version} from file {file}"); }
        });

        var selectedVersion = versions.Where(version =>
        {
            var otherSpec = new ModuleSpec(ModuleSpec.Name, ModuleSpec.Guid, RequiredVersion: version);
            var matchType = ModuleSpec.CompareTo(otherSpec);

            return matchType == ModuleMatch.Same || matchType == ModuleMatch.Stricter;
        }).OrderByDescending(version => version).FirstOrDefault();

        return selectedVersion == null ? null : _cachedFile = Path.Join(CachePath, $"{ModuleSpec.Name}.{selectedVersion}.nupkg");
    }

    public string CacheResult()
    {
        var versionString = ConvertVersionParameters(ModuleSpec.RequiredVersion?.ToString(), ModuleSpec.MinimumVersion?.ToString(), ModuleSpec.MaximumVersion?.ToString());
        var PowerShellCode = /*ps1*/ $$"""
        Set-PSResourceRepository -Name PSGallery -Trusted -Confirm:$False;

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

        if (!Directory.Exists(CachePath))
        {
            Directory.CreateDirectory(CachePath);
        }

        var pwsh = PowerShell.Create(RunspaceMode.NewRunspace);
        pwsh.RunspacePool = Program.RunspacePool.Value;
        pwsh.AddScript(PowerShellCode);
        var result = pwsh.Invoke();

        if (pwsh.HadErrors)
        {
            throw new Exception($"Failed to download module {ModuleSpec.Name} from the PowerShell Gallery. Error: {pwsh.Streams.Error[0].Exception.Message}");
        }

        var returnedResult = result.First().ToString();
        Logger.Debug($"Downloaded module {ModuleSpec.Name} from the PowerShell Gallery to {returnedResult}.");
        return returnedResult;
    }

    // Based on https://github.com/PowerShell/PowerShellGet/blob/c6aea39ea05491c648efd7aebdefab1ae7c5b213/src/PowerShellGet.psm1#L111-L144
    private static string? ConvertVersionParameters(
        string? requiredVersion,
        string? minimumVersion,
        string? maximumVersion) => (requiredVersion, minimumVersion, maximumVersion) switch
        {
            (null, null, null) => null,
            (string ver, null, null) => ver,
            (_, string min, null) => $"[{min},)",
            (_, null, string max) => $"(,{max}]",
            (_, string min, string max) => $"[{min},{max}]"
        };

    public override int GetHashCode() => ModuleSpec.GetHashCode();
}
