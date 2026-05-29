// Copyright (c) 2024, 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Diagnostics.Contracts;
using System.IO.Compression;
using System.Text;
using Compiler.Requirements;
using LanguageExt;

namespace Compiler.Module.Compiled;

public abstract class CompiledArchiveModule : Compiled {
    protected CompiledArchiveModule(
        ModuleSpec moduleSpec,
        RequirementGroup requirements,
        Lazy<Fin<byte[]>> contentBytes
    ) : base(moduleSpec, requirements, contentBytes) {
    }

    public override ContentType Type { get; } = ContentType.Zip;

    protected abstract string ArchiveModuleFolderName { get; }

    protected abstract string ArchiveEntryName { get; }

    [Pure]
    protected static byte[] CreateZipFromDirectory(string sourceDirectory) {
        using var memoryStream = new MemoryStream();
        using (var archive = new ZipArchive(memoryStream, ZipArchiveMode.Create, true)) {
            var files = Directory.GetFiles(sourceDirectory, "*", SearchOption.AllDirectories)
                .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
                .ToArray();

            foreach (var file in files) {
                var entryName = Path.GetRelativePath(sourceDirectory, file).Replace(Path.DirectorySeparatorChar, '/');
                var entry = archive.CreateEntry(entryName, CompressionLevel.Optimal);
                using var entryStream = entry.Open();
                using var fileStream = File.OpenRead(file);
                fileStream.CopyTo(entryStream);
            }
        }

        return memoryStream.ToArray();
    }

    public override Fin<string> StringifyContent() {
        if (this.GetContentBytes().IsErr(out var error, out var bytes)) return error;
        return $"'{Convert.ToBase64String((byte[])bytes)}'";
    }

    public override IEnumerable<string> GetExportedFunctions() => [];
}
