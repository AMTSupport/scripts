using System.Management.Automation.Language;
using CommandLine;

namespace Compiler
{
    public static class AstHelper
    {
        public static Dictionary<string, Dictionary<string, object>> FindDeclaredModules(Ast ast)
        {
            var modules = new Dictionary<string, Dictionary<string, object>>();

            foreach (var usingStatement in ast.FindAll(testAst => testAst is UsingStatementAst usingAst && usingAst.UsingStatementKind == UsingStatementKind.Module, true))
            {
                switch (usingStatement)
                {
                    case UsingStatementAst usingStatementAst when usingStatementAst.Name is not null:
                        modules.Add(usingStatementAst.Name.Value, []);
                        break;

                    case UsingStatementAst usingStatementAst when usingStatementAst.ModuleSpecification is not null:
                        var table = new Dictionary<string, object>();
                        var pairs = usingStatementAst.ModuleSpecification.KeyValuePairs.GetEnumerator();
                        while (pairs.MoveNext())
                        {
                            var key = pairs.Current.Item1.SafeGetValue().Cast<string>();
                            var value = pairs.Current.Item2.SafeGetValue().GetType();
                            table.Add(key, value);
                        }

                        if (!table.ContainsKey("ModuleName"))
                        {
                            throw new Exception("ModuleSpecification does not contain a 'ModuleName' key.");
                        }

                        foreach (var key in table.Keys)
                        {
                            if (key == "ModuleName")
                            {
                                continue;
                            }

                            if (key == "Guid" && table[key] is string guid)
                            {
                                table[key] = Guid.Parse(guid);
                            }

                            if (key.EndsWith("Version") && table[key] is string version)
                            {
                                table[key] = Version.Parse(version);
                            }
                        }

                        break;
                    default:
                        Console.WriteLine($"Unknown UsingStatementAst type from: {usingStatement}");
                        break;
                }
            }

            return modules;
        }
    }
}
