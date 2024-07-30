using System.Collections;
using System.IO.Compression;
using CommandLine;
using Compiler.Requirements;
using NLog;

namespace Compiler.Module.Compiled;

public class CompiledRemoteModule : Compiled
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private Hashtable? _powerShellManifest;
    private ZipArchive? _zipArchive;

    public readonly MemoryStream MemoryStream;

    public override ContentType Type => ContentType.ZipHex;

    public override Version Version { get; }

    internal CompiledRemoteModule(
        ModuleSpec moduleSpec,
        RequirementGroup requirements,
        MemoryStream memoryStream
    ) : base(moduleSpec, requirements, memoryStream.ToArray())
    {
        MemoryStream = memoryStream;

        var manifest = GetPowerShellManifest();
        Version = manifest["ModuleVersion"] switch
        {
            string version => Version.Parse(version),
            null => new Version(0, 0, 1),
            _ => throw new Exception($"ModuleVersion must be a string, but was {manifest["ModuleVersion"]?.GetType()}")
        };
    }

    public override string StringifyContent() => $"'{Convert.ToHexString(MemoryStream.ToArray())}'";

    public override IEnumerable<string> GetExportedFunctions()
    {
        var manifest = GetPowerShellManifest();

        var exportedFunctions = new List<string>();
        var functionsToExport = manifest["FunctionsToExport"] switch
        {
            string[] functions => functions,
            string function => [function],
            object[] functions => functions.Cast<string>(),
            null => [],
            _ => throw new Exception($"FunctionsToExport must be a string or an array of strings, but was {manifest["FunctionsToExport"]?.GetType()}")
        };
        var cmdletsToExport = manifest["CmdletsToExport"] switch
        {
            string[] cmdlets => cmdlets,
            string cmdlet => [cmdlet],
            object[] cmdlets => cmdlets.Cast<string>(),
            null => [],
            _ => throw new Exception($"CmdletsToExport must be a string or an array of strings, but was {manifest["CmdletsToExport"]?.GetType()}")
        };

        exportedFunctions.AddRange(functionsToExport);
        exportedFunctions.AddRange(cmdletsToExport);

        return exportedFunctions;
    }

    private ZipArchive GetZipArchive() => _zipArchive ??= new ZipArchive(MemoryStream, ZipArchiveMode.Read, true);

    private Hashtable GetPowerShellManifest()
    {
        if (_powerShellManifest != null) return _powerShellManifest;

        var archive = GetZipArchive();
        var psd1Entry = archive.GetEntry($"{ModuleSpec.Name}.psd1");
        if (psd1Entry == null)
        {
            Logger.Debug($"Failed to find the PSD1 file for module {ModuleSpec.Name}, assuming no requirements.");
            _powerShellManifest = [];
            return _powerShellManifest;
        }

        using var psd1Stream = psd1Entry.Open();
        if (Program.RunPowerShell(new StreamReader(psd1Stream).ReadToEnd())[0].BaseObject is not Hashtable psd1)
        {
            Logger.Debug($"Failed to parse the PSD1 file for module {ModuleSpec.Name}, assuming no requirements.");
            _powerShellManifest = [];
            return _powerShellManifest;
        }

        return _powerShellManifest = psd1;
    }
}
