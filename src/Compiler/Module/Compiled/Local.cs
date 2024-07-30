using System.Collections;
using System.Management.Automation.Language;
using System.Text;
using Compiler.Requirements;
using Compiler.Text;

namespace Compiler.Module.Compiled;


public class CompiledLocalModule : Compiled
{
    public override ContentType Type { get; } = ContentType.UTF8String;

    // Local modules are always version 0.0.1, as they are not versioned.
    public override Version Version { get; } = new Version(0, 0, 1);

    public readonly CompiledDocument Document;

    public readonly ScriptBlockAst Ast;

    public CompiledLocalModule(
        PathedModuleSpec moduleSpec,
        CompiledDocument document,
        RequirementGroup requirements
    ) : base(moduleSpec, requirements, Encoding.UTF8.GetBytes(document.GetContent()))
    {
        Document = document;
        Ast = AstHelper.GetAstReportingErrors(string.Join('\n', Document.Lines), moduleSpec.FullPath, ["ModuleNotFoundDuringParse"]);
    }

    public override string StringifyContent() => new StringBuilder()
        .AppendLine("<#ps1#> @'")
        .AppendJoin('\n', Requirements.GetRequirements().Select(requirement =>
        {
            var hash = requirement switch
            {
                ModuleSpec req => FindSibling(req)!.ComputedHash,
                _ => requirement.HashString
            };

            var data = new Hashtable() { { "NameSuffix", hash } };
            return requirement.GetInsertableLine(data);
        }))
        .AppendLine()
        .AppendLine(Document.GetContent())
        .Append("'@;")
        .ToString();

    public override IEnumerable<string> GetExportedFunctions() => AstHelper.FindAvailableFunctions(Ast, true).Select(function => function.Name);
}
