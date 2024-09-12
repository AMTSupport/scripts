// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.IO.Compression;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using CommandLine;
using Compiler.Requirements;
using LanguageExt;
using NLog;

namespace Compiler.Module.Compiled;

public class CompiledRemoteModule : Compiled {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private Hashtable? PowerShellManifest;
    private ZipArchive? ZipArchive;

    public readonly byte[] Bytes;

    public override ContentType Type => ContentType.Zip;

    public override Version Version { get; }

    public CompiledRemoteModule(
        ModuleSpec moduleSpec,
        RequirementGroup requirements,
        byte[] bytes
    ) : base(moduleSpec, requirements, bytes) {
        this.Bytes = bytes;

        var manifest = this.GetPowerShellManifest();
        this.Version = manifest["ModuleVersion"] switch {
            string version => Version.Parse(version),
            null => new Version(0, 0, 1),
            var other => throw new InvalidDataException($"ModuleVersion must be a string, but was {other.GetType()}")
        };
    }

    public override string StringifyContent() {
        var base64 = Convert.ToBase64String(this.Bytes);
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

                var sessionState = InitialSessionState.CreateDefault2();
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
                throw new InvalidDataException($"FunctionsToExport must be a string or an array of strings, but was {data.GetType()}");
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

    private ZipArchive GetZipArchive() => this.ZipArchive ??= new ZipArchive(new MemoryStream((byte[])this.Bytes.Clone()), ZipArchiveMode.Read, false);

    private Hashtable GetPowerShellManifest() {
        if (this.PowerShellManifest != null) return this.PowerShellManifest;

        var archive = this.GetZipArchive();
        ZipArchiveEntry? psd1Entry;
        try {
            psd1Entry = archive.GetEntry($"{this.ModuleSpec.Name}.psd1");
        } catch (InvalidDataException err) {
            Logger.Error($"Unable to open entry for {this.ModuleSpec.Name} to find the PSD1 file: {err.Message}");
            return this.PowerShellManifest = [];
        }

        if (psd1Entry == null) {
            this.PowerShellManifest = [];
            return this.PowerShellManifest;
        }

        using var psd1Stream = psd1Entry.Open();
        using var psd1Reader = new StreamReader(psd1Stream);
        var psd1String = psd1Reader.ReadToEnd();

        return Program.RunPowerShell(psd1String)
            .Map(objects => (Hashtable)objects[0].BaseObject)
            .Match(
                Succ: psd1 => this.PowerShellManifest = psd1,
                Fail: err => {
                    Logger.Debug($"Failed to parse the PSD1 file for module {this.ModuleSpec.Name}, assuming no requirements.");
                    return this.PowerShellManifest = [];
                }
            );
    }
}
