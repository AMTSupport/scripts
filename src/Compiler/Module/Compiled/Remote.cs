// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.IO.Compression;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using CommandLine;
using Compiler.Requirements;
using NLog;

namespace Compiler.Module.Compiled;

public class CompiledRemoteModule : Compiled {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private Hashtable? PowerShellManifest;
    private ZipArchive? ZipArchive;

    public readonly MemoryStream MemoryStream;

    public override ContentType Type => ContentType.Zip;

    public override Version Version { get; }

    internal CompiledRemoteModule(
        ModuleSpec moduleSpec,
        RequirementGroup requirements,
        MemoryStream memoryStream
    ) : base(moduleSpec, requirements, memoryStream.ToArray()) {
        this.MemoryStream = memoryStream;

        var manifest = this.GetPowerShellManifest();
        this.Version = manifest["ModuleVersion"] switch {
            string version => Version.Parse(version),
            null => new Version(0, 0, 1),
            _ => throw new Exception($"ModuleVersion must be a string, but was {manifest["ModuleVersion"]?.GetType()}")
        };
    }

    public override string StringifyContent() {
        // Convert to a powershell byte array
        var bytes = new byte[this.MemoryStream.Length];
        this.MemoryStream.Read(bytes, 0, bytes.Length);
        var base64 = Convert.ToBase64String(bytes);
        return $"'{base64}'";
    }

    public IEnumerable<string> GetExported(object? data, CommandTypes commandTypes) {
        switch (data) {
            case object[] strings:
                return strings.Cast<string>();
            case string starString when starString == "*":
                var version = this.GetPowerShellManifest()["ModuleVersion"]!.ToString()!;
                var tempModuleRootPath = Path.Combine(Path.GetTempPath(), $"PowerShellGet\\_Export_{this.ModuleSpec.Name}");
                var tempOutput = Path.Combine(tempModuleRootPath, this.ModuleSpec.Name, version);
                if (!Directory.Exists(tempOutput)) {
                    Directory.CreateDirectory(tempOutput);
                    using var archive = this.GetZipArchive();
                    archive.ExtractToDirectory(tempOutput);
                }

                var sessionState = InitialSessionState.CreateDefault();
                sessionState.ImportPSModulesFromPath(tempModuleRootPath);
                var pwsh = PowerShell.Create(sessionState);
                return pwsh.Runspace.SessionStateProxy.InvokeCommand
                    .GetCommands("*", commandTypes, true)
                    .Where(command => command.ModuleName == this.ModuleSpec.Name)
                    .Select(command => command.Name);
            case string str:
                return [str];
            case null:
                return [];
            default:
                throw new Exception($"FunctionsToExport must be a string or an array of strings, but was {data.GetType()}");
        }
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

    private ZipArchive GetZipArchive() => this.ZipArchive ??= new ZipArchive(this.MemoryStream, ZipArchiveMode.Read, true);


        var archive = GetZipArchive();
        var psd1Entry = archive.GetEntry($"{ModuleSpec.Name}.psd1");
        if (psd1Entry == null)
        {
            Logger.Debug($"Failed to find the PSD1 file for module {ModuleSpec.Name}, assuming no requirements.");
            _powerShellManifest = [];
            return _powerShellManifest;
        }
    private Hashtable GetPowerShellManifest() {
        if (this.PowerShellManifest != null) return this.PowerShellManifest;

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
