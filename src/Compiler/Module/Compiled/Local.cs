// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.Diagnostics.CodeAnalysis;
using System.Diagnostics.Contracts;
using System.Text;
using Compiler.Requirements;
using Compiler.Text;
using LanguageExt;
using LanguageExt.Common;

namespace Compiler.Module.Compiled;

public class CompiledLocalModule : Compiled {
    public override ContentType Type { get; } = ContentType.UTF8String;

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
        this.SetContentBytes(new(() => this.StringifyContent().Map(Encoding.UTF8.GetBytes)));
    }

    public override Fin<string> StringifyContent() {
        var content = new StringBuilder()
            .AppendLine("<#ps1#> @'");

        foreach (var requirement in this.Requirements.GetRequirements()) {
            var hashResult = requirement switch {
                ModuleSpec req => this.FindSibling(req) is { } sibling
                    ? sibling.ComputedHash().Map(hash => hash[..6])
                    : Fin<string>.Fail(Error.New($"Missing compiled sibling for module requirement {requirement} in {this.ModuleSpec.Name}.")),
                _ => Fin<string>.Succ(requirement.HashString[..6])
            };

            if (hashResult.IsErr(out var err, out var hash)) {
                return err;
            }

            var data = new Hashtable() { { "NameSuffix", hash } };
            content.AppendLine(requirement.GetInsertableLine(data));
        }

        content.AppendLine()
            .AppendLine(this.Document.GetContent())
            .Append("'@;");

        return content.ToString();
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
