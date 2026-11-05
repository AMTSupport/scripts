// Copyright (c) 2024, 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections;
using System.Diagnostics.CodeAnalysis;
using System.Diagnostics.Contracts;
using System.IO.Compression;
using System.Text;
using Compiler.Requirements;
using Compiler.Text;
using LanguageExt;

namespace Compiler.Module.Compiled;

public class CompiledLocalModule : Compiled {
    public override ContentType Type { get; } = ContentType.UTF8String;

    public override ContentCompression Compression { get; }

    // Local modules are always version 0.0.1, as they are not versioned.
    public override Version Version { get; } = new Version(0, 0, 1);

    public virtual CompiledDocument Document { get; }

    private readonly EmbeddedLocalTextCompression CompressionMode;

    private readonly CompressionLevel CompressionLevel;

    public CompiledLocalModule(
        PathedModuleSpec moduleSpec,
        CompiledDocument document,
        RequirementGroup requirements
    ) : base(moduleSpec, requirements) {
        this.Document = document;
        this.CompressionMode = CompilerSettings.EmbeddedLocalTextCompression;
        this.CompressionLevel = CompilerSettings.EmbeddedLocalTextCompressionLevel;
        this.Compression = this.CompressionMode == EmbeddedLocalTextCompression.None ? ContentCompression.None : ContentCompression.GZip;
        this.SetContentBytes(new(this.GetRawContentBytes));
    }

    [Pure]
    protected virtual Fin<byte[]> GetRawContentBytes() {
        var content = new StringBuilder();

        foreach (var requirement in this.Requirements.GetRequirements()) {
            var hashResult = requirement switch {
                ModuleSpec req => this.FindSibling(req) is { } sibling
                    ? sibling.GetNameHash().Map(hash => hash[(sibling.ModuleSpec.Name.Length + 1)..])
                    : Fin.Fail<string>(Error.New($"Missing compiled sibling for module requirement {requirement} in {this.ModuleSpec.Name}.")),
                _ => Pure(requirement.HashString[..6])
            };

            if (hashResult.IsErr(out var err, out var hash)) {
                return err;
            }

            var data = new Hashtable() { { "NameSuffix", hash } };
            content.AppendLine(requirement.GetInsertableLine(data));
        }

        content.AppendLine()
            .Append(this.Document.GetContent());

        return Encoding.UTF8.GetBytes(content.ToString());
    }

    public override Fin<string> StringifyContent() =>
        this.GetRawContentBytes().Map(bytes => this.CompressionMode == EmbeddedLocalTextCompression.None
            ? $"'{Encoding.UTF8.GetString(bytes).Replace("'", "''")}'"
            : $"'{Convert.ToBase64String(Compress(bytes, this.CompressionLevel))}'");

    /// <summary>Returns the raw payload bytes as they appear in the embedded output (compressed or raw).</summary>
    internal Fin<byte[]> GetEmbeddedPayloadBytes() =>
        this.GetRawContentBytes().Map(bytes => this.CompressionMode == EmbeddedLocalTextCompression.None
            ? bytes
            : Compress(bytes, this.CompressionLevel));

    protected static byte[] Compress(byte[] bytes, CompressionLevel compressionLevel) {
        using var output = new MemoryStream();
        using (var gzip = new GZipStream(output, compressionLevel, true)) {
            gzip.Write(bytes, 0, bytes.Length);
        }

        return output.ToArray();
    }

    public Fin<Unit> ValidateRequirementsResolved() {
        foreach (var requirement in this.Requirements.GetRequirements<ModuleSpec>()) {

            if (this.FindSibling(requirement) is null) {
                return Error.New($"Missing compiled sibling for module requirement {requirement} in {this.ModuleSpec.Name}.");
            }
        }

        return Unit.Default;
    }

    [ExcludeFromCodeCoverage(Justification = "We don't need to test this, as it's just a wrapper.")]
    public override IEnumerable<string> GetExportedFunctions() {
        var exported = new List<string>();
        exported.AddRange(AstHelper.FindAvailableFunctions(this.Document.Ast, true).Select(function => function.Name));
        exported.AddRange(AstHelper.FindAvailableAliases(this.Document.Ast, true));
        return exported;
    }
}
