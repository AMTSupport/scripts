// Copyright (c) 2024, 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections;
using System.Diagnostics.CodeAnalysis;
using System.Diagnostics.Contracts;
using System.Text;
using Compiler.Requirements;
using Compiler.Text;
using LanguageExt;

namespace Compiler.Module.Compiled;

public class CompiledLocalModule : Compiled {
    public override ContentType Type { get; } = ContentType.Base64Utf8;

    // Local modules are always version 0.0.1, as they are not versioned.
    public override Version Version { get; } = new Version(0, 0, 1);

    public virtual CompiledDocument Document { get; }

    [Pure]
    public CompiledLocalModule(
        PathedModuleSpec moduleSpec,
        CompiledDocument document,
        RequirementGroup requirements
    ) : base(moduleSpec, requirements) {
        this.Document = document;
        this.SetContentBytes(new(() => this.GetRawContentText().Map(text => Encoding.UTF8.GetBytes(text))));
    }

    [Pure]
    protected virtual Fin<string> GetRawContentText() {
        var content = new StringBuilder();

        foreach (var requirement in this.Requirements.GetRequirements()) {
            var hashResult = requirement switch {
                ModuleSpec req => this.FindSibling(req) is { } sibling
                    ? sibling.GetIdentityHash().Map(hash => hash[..6])
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

        return content.ToString();
    }

    public override Fin<string> StringifyContent() =>
        this.GetRawContentText().Map(text => $"'{Convert.ToBase64String(Encoding.UTF8.GetBytes(text))}'");

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
