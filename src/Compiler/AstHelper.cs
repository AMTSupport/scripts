// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics.CodeAnalysis;
using System.Management.Automation;
using System.Management.Automation.Language;
using System.Text;
using NLog;
using Pastel;

namespace Compiler;

public static class AstHelper {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public static Dictionary<string, Dictionary<string, object>> FindDeclaredModules(Ast ast) {
        var modules = new Dictionary<string, Dictionary<string, object>>();

        foreach (var usingStatement in ast.FindAll(testAst => testAst is UsingStatementAst usingAst && usingAst.UsingStatementKind == UsingStatementKind.Module, true)) {
            switch (usingStatement) {
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
                    while (pairs.MoveNext()) {
                        var key = (string)pairs.Current.Item1.SafeGetValue();
                        var value = pairs.Current.Item2.SafeGetValue();
                        table.Add(key, value);
                    }

                    if (!table.TryGetValue("ModuleName", out var moduleName)) throw new Exception("ModuleSpecification does not contain a 'ModuleName' key.");
                    if (table.TryGetValue("Guid", out var guid)) table["Guid"] = Guid.Parse((string)guid);
                    foreach (var versionKey in new[] { "ModuleVersion", "MaximumVersion", "RequiredVersion" }) {
                        if (table.TryGetValue(versionKey, out var version)) table[versionKey] = Version.Parse((string)version);
                    }

                    modules.Add((string)moduleName, table);
                    break;
                default:
                    Logger.Error($"Unknown UsingStatementAst type from: {usingStatement}");
                    break;
            }
        }

        if (ast is ScriptBlockAst scriptBlockAst) {
            if (scriptBlockAst.ScriptRequirements is null) return modules;

            scriptBlockAst.ScriptRequirements.RequiredModules.ToList().ForEach(module => {
                Logger.Debug($"Found required module: {module.Name}");

                var table = new Dictionary<string, object>();
                if (module.Version is not null) table.Add("ModuleVersion", module.Version);
                if (module.MaximumVersion is not null) table.Add("MaximumVersion", module.MaximumVersion);
                if (module.RequiredVersion is not null) table.Add("RequiredVersion", module.RequiredVersion);
                if (module.Guid is not null) table.Add("Guid", module.Guid);

                modules.TryAdd(module.Name, table);
            });
        }

        return modules;
    }

    public static List<(string, UsingStatementAst)> FindDeclaredNamespaces(Ast ast) {
        var namespaces = new List<(string, UsingStatementAst)>();

        ast.FindAll(testAst => testAst is UsingStatementAst usingAst && usingAst.UsingStatementKind == UsingStatementKind.Namespace, true)
            .Cast<UsingStatementAst>()
            .ToList()
            .ForEach(usingStatement => {
                if (usingStatement.Name is null) throw new Exception("UsingStatementAst does not contain a Name.");
                namespaces.Add((usingStatement.Name.Value, usingStatement));
            });

        return namespaces;
    }

    public static List<FunctionDefinitionAst> FindAvailableFunctions(Ast ast, bool onlyExported) {
        var allDefinedFunctions = ast
            .FindAll(testAst => testAst is FunctionDefinitionAst, true)
            .Cast<FunctionDefinitionAst>()
            .ToList();

        // If there is no export command or we are not filtering for only exported functions, return all functions.
        if (ast.Find(testAst => !onlyExported || (testAst is CommandAst commandAst && commandAst.CommandElements[0].Extent.Text == "Export-ModuleMember"), true) is not CommandAst command) {
            return allDefinedFunctions;
        }

        // TODO - Support using * to export all of a type.
        var wantingToExport = new List<(string, List<string>)>();
        var namedParameters = ast.FindAll(testAst => testAst is CommandParameterAst commandParameter && commandParameter.Parent == command, true).Cast<CommandParameterAst>().ToList();
        foreach (var (namedParameter, index) in namedParameters.Select((value, i) => (value, i))) {
            if (namedParameter.ParameterName is not "Function" and not "Alias") {
                continue;
            }

            var value = namedParameter.Argument;
            value ??= command.CommandElements[command.CommandElements.IndexOf(namedParameter) + 1] as ExpressionAst;

            var objects = value switch {
                StringConstantExpressionAst stringConstantExpressionAst => [stringConstantExpressionAst.Value],
                ArrayLiteralAst arrayLiteralAst => arrayLiteralAst.Elements.Select(element => element.SafeGetValue()),
                _ => throw new NotImplementedException($"Export-ModuleMember parameter must be a string or array of strings, got: {value}"),
            };

            wantingToExport.Add((namedParameter.ParameterName, objects.Cast<string>().ToList()));
        }

        return allDefinedFunctions
            .Where(function => {
                // If the name is scoped to a namespace, remove the namespace.
                var name = function.Name.Contains(':') ? function.Name.Split(':').Last() : function.Name;
                return wantingToExport.Any(wanting => wanting.Item2.Contains(name));
            }).ToList();
    }

    /// <summary>
    /// Parse the given content into an AST, reporting any errors.
    /// </summary>
    /// <param name="astContent">
    /// The content to parse into the AST.
    /// </param>
    /// <param name="filePath">
    /// The file path of the content, or None if it is not from a file.
    /// </param>
    /// <param name="ignoredErrors">
    /// A list of ErrorIds to ignore if they are encountered.
    /// </param>
    /// <returns>
    /// The AST of the content if it was successfully parsed.
    /// </returns>
        [NotNull] string astContent,
        string? filePath,
        [NotNull] IEnumerable<string> ignoredErrors)
    {
        ArgumentNullException.ThrowIfNull(ignoredErrors, nameof(ignoredErrors));

        var ast = System.Management.Automation.Language.Parser.ParseInput(astContent, filePath, out _, out var parserErrors);
        parserErrors = [.. parserErrors.Where(error => !ignoredErrors.Contains(error.ErrorId))];

        {
            foreach (var error in parserErrors)
            {
                Program.Issues.Add(
                    new Analyser.Issue(
                        Analyser.IssueSeverity.Error,
                        error.Message,
                        error.Extent,
                        ast
                    )
                );
            }

            throw new ParseException($"Failed to parse {filePath}, encountered {parserErrors.Length} errors.");
        if (parserErrors.Length != 0) {
        }

        return ast;
    }

    // TODO, ability to translate the virtual cleaned line numbers to the actual line numbers in the file.
    public static void PrintPrettyAstError(
        [NotNull] IScriptExtent extent,
        [NotNull] Ast parentAst,
        [NotNull] string message)
    {
        ArgumentNullException.ThrowIfNull(extent);
        ArgumentNullException.ThrowIfNull(parentAst);
        ArgumentNullException.ThrowIfNull(message);

        var startingLine = extent.StartLineNumber;
        var endingLine = extent.EndLineNumber;
        var startingColumn = extent.StartColumnNumber - 1;
        var endingColumn = extent.EndColumnNumber - 1;

        var firstColumnIndent = Math.Max(endingLine.ToString(CultureInfo.InvariantCulture).Length + 1, 5);
        var firstColumnIndentString = new string(' ', firstColumnIndent);
        var colouredPipe = "|".Pastel(ConsoleColor.Cyan);

        while (parentAst.Parent != null) {
            parentAst = parentAst.Parent;
        };
        var extentRegion = parentAst.Extent.Text.Split('\n')[(startingLine - 1)..endingLine];

        var printableLines = new string[extentRegion.Length];
        for (var i = 0; i < extentRegion.Length; i++) {
            var line = extentRegion[i];
            line = i switch {
                0 when i == extentRegion.Length - 1 => string.Concat(line[0..startingColumn], line[startingColumn..endingColumn].Pastel(ConsoleColor.DarkRed), line[endingColumn..]),
                0 => string.Concat(line[0..startingColumn], line[startingColumn..].Pastel(ConsoleColor.DarkRed)),
                var _ when i == extentRegion.Length - 1 => string.Concat(line[0..endingColumn].Pastel(ConsoleColor.DarkRed), line[endingColumn..]),
                _ => line.Pastel(ConsoleColor.DarkRed)
            };

            var sb = new StringBuilder()
                .Append((i + startingLine).ToString(CultureInfo.InvariantCulture).PadRight(firstColumnIndent).Pastel(ConsoleColor.Cyan))
                .Append(colouredPipe)
                .Append(' ')
                .Append(line);

            printableLines[i] = sb.ToString();
        }

        string errorPointer;
        if (startingLine == endingLine) {
            errorPointer = string.Concat([new(' ', startingColumn), new('~', endingColumn - startingColumn)]);
        } else {
            var squigleEndColumn = extentRegion.Max(line => line.TrimEnd().Length);
            var leastWhitespaceBeforeText = extentRegion.Min(line => line.Length - line.TrimStart().Length);
            errorPointer = string.Concat([new(' ', leastWhitespaceBeforeText), new('~', squigleEndColumn - leastWhitespaceBeforeText)]);
        }

        var fileName = parentAst.Extent.File is null ? "Unknown file" : parentAst.Extent.File;

        return $"""
        {"File".PadRight(firstColumnIndent).Pastel(ConsoleColor.Cyan)}{colouredPipe} {fileName.Pastel(ConsoleColor.Gray)}
        {"Line".PadRight(firstColumnIndent).Pastel(ConsoleColor.Cyan)}{colouredPipe}
        {string.Join('\n', printableLines)}
        {firstColumnIndentString}{colouredPipe} {errorPointer.Pastel(ConsoleColor.DarkRed)}
        {firstColumnIndentString}{colouredPipe} {message.Pastel(ConsoleColor.DarkRed)}
        """);
    }

    public static ParamBlockAst? FindClosestParamBlock(Ast ast) {
        var parent = ast;
        while (parent != null) {
            if (parent is ScriptBlockAst scriptBlock && scriptBlock.ParamBlock != null) return scriptBlock.ParamBlock;
            parent = parent.Parent;
        }

        return null;
    }

    [return: NotNullIfNotNull(nameof(ast))]
    public static Ast FindRoot([NotNull] Ast ast) {
        ArgumentNullException.ThrowIfNull(ast);

        var parent = ast;
        while (parent.Parent != null) {
            parent = parent.Parent;
        }

        return parent;
    }
}
