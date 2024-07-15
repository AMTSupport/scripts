
using System.Collections;
using System.Management.Automation.Language;
using System.Security.Cryptography;
using System.Text;
using Compiler.Requirements;
using Compiler.Text;

namespace Compiler.Module.Compiled;


public class CompiledLocalModule : Compiled
{
    public readonly CompiledDocument Document;

    public readonly ScriptBlockAst Ast;

    public override string ComputedHash
    {
        get
        {
            var hashableBytes = Encoding.UTF8.GetBytes(Document.GetContent()).ToList();

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

    public override ContentType ContentType => ContentType.UTF8String;

    /// <summary>
    /// A local modules version is always 0.0.1.
    /// </summary>
    public override Version Version => Version.Parse("0.0.1");

    public CompiledLocalModule(PathedModuleSpec moduleSpec, CompiledDocument document) : base(moduleSpec)
    {
        Document = document;
        Ast = AstHelper.GetAstReportingErrors(string.Join('\n', Document.Lines), moduleSpec.FullPath, ["ModuleNotFoundDuringParse"]);
    }

    public override string StringifyContent() => new StringBuilder()
        .AppendLine("<#ps1#> @'")
        .AppendJoin('\n', Requirements.GetRequirements().Select(requirement =>
        {
            var data = new Hashtable() { { "NameSuffix", Convert.ToHexString(requirement.Hash) } };
            return requirement.GetInsertableLine(data);
        }))
        .AppendLine()
        .AppendLine(Document.GetContent())
        .Append("'@;")
        .ToString();

    public override IEnumerable<string> GetExportedFunctions() => AstHelper.FindAvailableFunctions(Ast, true).Select(function => function.Name);
}
