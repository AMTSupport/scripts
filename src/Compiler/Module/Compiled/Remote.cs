using System.Collections;
using System.IO.Compression;
using System.Security.Cryptography;
using CommandLine;
using Compiler.Requirements;
using NLog;
using NLog.LayoutRenderers;

namespace Compiler.Module.Compiled;

public class CompiledRemoteModule(ModuleSpec moduleSpec) : Compiled(moduleSpec)
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private Hashtable? _powerShellManifest;
    private ZipArchive? _zipArchive;

    public required MemoryStream MemoryStream { get; init; }

    public override string ComputedHash
    {
        get
        {
            var hashableBytes = MemoryStream.ToArray().ToList();

            var requirements = Requirements.GetRequirements();
            if (requirements.IsEmpty)
            {
                Requirements.GetRequirements().ToList().ForEach(requirement =>
                {
                    hashableBytes.AddRange(requirement.Hash);
                });
            }

            return Convert.ToHexString(SHA1.HashData([.. hashableBytes]));
        }
    }

    public override ContentType ContentType => ContentType.ZipHex;

    public override Version Version
    {
        get
        {
            var manifest = GetPowerShellManifest();
            if (manifest["ModuleVersion"] is string version) return Version.Parse(version);
            return new Version(0, 0, 1);
        }
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
