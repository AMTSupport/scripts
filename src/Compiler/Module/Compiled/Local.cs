// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.Management.Automation.Language;
using System.Text;
using Compiler.Requirements;
using Compiler.Text;

namespace Compiler.Module.Compiled;


public class CompiledLocalModule : Compiled {
    public override ContentType Type { get; } = ContentType.UTF8String;

    // Local modules are always version 0.0.1, as they are not versioned.
    public override Version Version { get; } = new Version(0, 0, 1);

    public readonly CompiledDocument Document;

    public readonly ScriptBlockAst Ast;

    public CompiledLocalModule(
        PathedModuleSpec moduleSpec,
        CompiledDocument document,
        RequirementGroup requirements
    ) : base(moduleSpec, requirements, Encoding.UTF8.GetBytes(document.GetContent())) {
        this.Document = document;
        this.Ast = AstHelper.GetAstReportingErrors(string.Join('\n', this.Document.Lines), Some(moduleSpec.FullPath), ["ModuleNotFoundDuringParse"]).ThrowIfFail();
    }

    public override string StringifyContent() => new StringBuilder()
        .AppendLine("<#ps1#> @'")
        .AppendJoin('\n', this.Requirements.GetRequirements().Select(requirement => {
            var hash = (requirement switch {
                ModuleSpec req => this.FindSibling(req)!.ComputedHash,
                _ => requirement.HashString
            })[..6];

            var data = new Hashtable() { { "NameSuffix", hash } };
            return requirement.GetInsertableLine(data);
        }))
        .AppendLine()
        .AppendLine(this.Document.GetContent())
        .Append("'@;")
        .ToString();

    public override IEnumerable<string> GetExportedFunctions() => AstHelper.FindAvailableFunctions(this.Ast, true).Select(function => function.Name);
}
