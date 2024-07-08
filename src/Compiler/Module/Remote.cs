using System.Management.Automation;
using System.Management.Automation.Runspaces;
using Compiler.Requirements;
using NLog;

namespace Compiler.Module;

public class RemoteModule(ModuleSpec moduleSpec) : Module(moduleSpec)
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    private string CachePath => Path.Join(
        Path.GetTempPath(),
        "PowerShellGet",
        ModuleSpec.Name
    );

    public Lazy<byte[]> ZipBytes => new(() => File.ReadAllBytes(FindCachedResult() ?? CacheResult()));

    public override ModuleMatch GetModuleMatchFor(ModuleSpec requirement)
    {
        return ModuleSpec.CompareTo(requirement);
    }

    public string? FindCachedResult()
    {
        if (!Directory.Exists(CachePath))
        {
            return null;
        }

        var files = Directory.GetFiles(CachePath, "*.nupkg");
        if (files.Length == 0)
        {
            return null;
        }

        var versions = files.Select(file =>
        {
            var fileName = Path.GetFileName(file);
            var version = fileName.Substring(ModuleSpec.Name.Length + 1, fileName.Length - ModuleSpec.Name.Length - 1 - ".nupkg".Length);
            return new Version(version);
        });

        var selectedVersion = versions.Where(version =>
        {
            var otherSpec = new ModuleSpec(ModuleSpec.Name, ModuleSpec.Guid, RequiredVersion: version);
            var matchType = ModuleSpec.CompareTo(otherSpec);

            return matchType == ModuleMatch.Same || matchType == ModuleMatch.Stricter;
        }).OrderByDescending(version => version).FirstOrDefault();

        return selectedVersion == null ? null : Path.Join(CachePath, $"{ModuleSpec.Name}.{selectedVersion}.nupkg");
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
            $Module | Save-PSResource -Path '{{CachePath}}' -AsNupkg;
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
}
