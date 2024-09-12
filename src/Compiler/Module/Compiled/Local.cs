// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.Diagnostics.CodeAnalysis;
using System.Text;
using Compiler.Requirements;
using Compiler.Text;
using LanguageExt;

namespace Compiler.Module.Compiled;


public class CompiledLocalModule(
    PathedModuleSpec moduleSpec,
    CompiledDocument document,
    RequirementGroup requirements
) : Compiled(moduleSpec, requirements, Encoding.UTF8.GetBytes(document.GetContent())) {
    public override ContentType Type { get; } = ContentType.UTF8String;

    // Local modules are always version 0.0.1, as they are not versioned.
    public override Version Version { get; } = new Version(0, 0, 1);

    public virtual CompiledDocument Document { get; } = document;

    public override string StringifyContent() => new StringBuilder()
        .AppendLine("<#ps1#> @'")
        .AppendJoin('\n', this.Requirements.GetRequirements().Select(requirement => {
            string hash;
            try {
                hash = (requirement switch {
                    ModuleSpec req => this.FindSibling(req)!.ComputedHash,
                    _ => requirement.HashString
                })[..6];
            } catch {
                hash = "000000";
            }

            var data = new Hashtable() { { "NameSuffix", hash } };
            return requirement.GetInsertableLine(data);
        }))
        .AppendLine()
        .AppendLine(this.Document.GetContent())
        .Append("'@;")
        .ToString();

    [ExcludeFromCodeCoverage(Justification = "We don't need to test this, as it's just a wrapper.")]
    public override IEnumerable<string> GetExportedFunctions() =>
        AstHelper.FindAvailableFunctions(this.Document.Ast, true).Select(function => function.Name);
}
