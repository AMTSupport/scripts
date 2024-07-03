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
                        modules.Add(usingStatementAst.Name.Value, new Dictionary<string, object> {
                            { "AST", usingStatementAst }
                        });
                        break;

                    case UsingStatementAst usingStatementAst when usingStatementAst.ModuleSpecification is not null:
                        var table = new Dictionary<string, object>
                        {
                            { "AST", usingStatementAst }
                        };
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
        public static List<(string, UsingStatementAst)> FindDeclaredNamespaces(Ast ast)
        {
            var namespaces = new List<(string, UsingStatementAst)>();

            ast.FindAll(testAst => testAst is UsingStatementAst usingAst && usingAst.UsingStatementKind == UsingStatementKind.Namespace, true)
                .Cast<UsingStatementAst>()
                .ToList()
                .ForEach(usingStatement =>
                {
                    Logger.Debug($"Found namespace: {usingStatement}");

                    if (usingStatement.Name is null)
                    {
                        throw new Exception("UsingStatementAst does not contain a Name.");
                    }

                    namespaces.Add((usingStatement.Name.Value, usingStatement));
                });

            return namespaces;
        }

        public static List<CommandAst> FindCalledFunctions(Ast ast) => [.. ast.FindAll(testAst => testAst is CommandAst, true).Cast<CommandAst>().Where(command => command.GetCommandName() != null)];

        public static List<FunctionDefinitionAst> FindAvailableFunctions(Ast ast, bool onlyExported)
        {
            // Check for Export-ModuleMember statement, if one exists return only functions listed
            // Otherwise return all functions
            var allDefinedFunctions = ast.FindAll(testAst => testAst is FunctionDefinitionAst, true).Cast<FunctionDefinitionAst>().ToList();

            if (ast.Find(testAst => testAst is CommandAst commandAst && commandAst.CommandElements[0].Extent.Text == "Export-ModuleMember", true) is not CommandAst command || !onlyExported)
            {
                return allDefinedFunctions;
            }

            var wantingToExport = new List<(string, List<string>)>();
            var namedParameters = ast.FindAll(testAst => testAst is CommandParameterAst commandParameter && commandParameter.Parent == command, true).Cast<CommandParameterAst>().ToList();
            foreach (var (namedParameter, index) in namedParameters.Select((value, i) => (value, i)))
            {
                ExpressionAst? value = namedParameter.Argument;
                value ??= command.CommandElements[index + 1] as ExpressionAst;

                var objects = value switch
                {
                    StringConstantExpressionAst stringConstantExpressionAst => [stringConstantExpressionAst.Value],
                    ArrayLiteralAst arrayLiteralAst => arrayLiteralAst.Elements.Select(element => element.SafeGetValue()),
                    _ => throw new NotImplementedException("Export-ModuleMember parameter must be a string or array of strings"),
                };
            }

            return allDefinedFunctions.Where(function => wantingToExport.Any(wanting => wanting.Item2.Contains(function.Name))).ToList();
        }
    }
}
