using System.Management.Automation.Language;
using CommandLine;
using NLog;

namespace Compiler
{
    public static class AstHelper
    {
        private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

        public static Dictionary<string, Dictionary<string, object>> FindDeclaredModules(Ast ast)
        {
            var modules = new Dictionary<string, Dictionary<string, object>>();

            foreach (var usingStatement in ast.FindAll(testAst => testAst is UsingStatementAst usingAst && usingAst.UsingStatementKind == UsingStatementKind.Module, true))
            {
                Logger.Debug($"Found module: {usingStatement}");

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
                            var value = pairs.Current.Item2.SafeGetValue();
                            table.Add(key, value);
                        }

                        if (!table.ContainsKey("ModuleName"))
                        {
                            throw new Exception("ModuleSpecification does not contain a 'ModuleName' key.");
                        }

                        foreach (var key in table.Keys)
                        {
                            Logger.Debug($"Key: {key}, Value: {table[key]}");

                            if (key == "Guid" && table[key] is string guid)
                            {
                                table[key] = Guid.Parse(guid);
                            }

                            // if (key.EndsWith("Version") && table[key] is string version)
                            // {
                            //     table[key] = Version.Parse(version);
                            // }
                        }

                        Logger.Debug($"Adding {table["ModuleName"] as string} with value {table}");
                        modules.Add((table["ModuleName"] as string)!, table);
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
