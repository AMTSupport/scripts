using System;
using System.Collections.Generic;
using System.Management.Automation.Language;
using System.Text.RegularExpressions;
using CommandLine;
using Microsoft.PowerShell.Commands;

public static class AstHelepr
{
    public static Dictionary<string, Dictionary<string, object>> FindDeclaredModules(Ast ast)
    {
        var modules = new Dictionary<string, Dictionary<string, object>>();

        foreach (var usingStatement in ast.FindAll(testAst => testAst is UsingStatementAst && ((UsingStatementAst)testAst).UsingStatementKind == UsingStatementKind.Module, true))
        {
            switch (usingStatement)
            {
                case UsingStatementAst usingStatementAst when usingStatementAst.Name is StringConstantExpressionAst:
                    modules.Add(usingStatementAst.Name.Value, new Dictionary<string, object>());
                    break;

                case UsingStatementAst usingStatementAst when usingStatementAst.ModuleSpecification is HashtableAst:
                    var table = new Dictionary<string, object>();
                    var pairs = usingStatementAst.ModuleSpecification.KeyValuePairs.GetEnumerator();
                    while (pairs.MoveNext())
                    {
                        var key = pairs.Current.Item1.SafeGetValue().Cast<StringConstantExpressionAst>().Value;
                        var value = new InvokeExpressionCommand
                        {
                            Command = pairs.Current.Item2.SafeGetValue().ToString()
                        }.Invoke().GetEnumerator().Current.GetType();

                        table.Add(key, value);
                    }

                    if (!table.ContainsKey("ModuleName"))
                    {
                        throw new Exception("ModuleSpecification does not contain a 'ModuleName' key.");
                    }

                    modules.Add(table["ModuleName"].ToString(), table);
                    break;
                default:
                    Console.WriteLine($"Unknown UsingStatementAst type from: {usingStatement}");
                    break;
            }
        }

        return modules;
    }

    public static (int, int) FindStartToEndBlock(string[] lines, string openPattern, string closePattern)
    {
        if (lines == null || lines.Length == 0)
        {
            return (-1, -1);
        }

        int startIndex = -1;
        int endIndex = -1;
        int openLevel = 0;
        for (int index = 0; index < lines.Length; index++)
        {
            string line = lines[index];

            if (Regex.IsMatch(line, openPattern))
            {
                if (openLevel == 0)
                {
                    startIndex = index;
                }

                openLevel += Regex.Matches(line, openPattern).Count;
            }

            if (Regex.IsMatch(line, closePattern))
            {
                openLevel -= Regex.Matches(line, closePattern).Count;

                if (openLevel == 0)
                {
                    endIndex = index;
                    break;
                }
            }
        }

        return (startIndex, endIndex);
    }
}
