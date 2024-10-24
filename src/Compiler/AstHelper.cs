// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Language;
using System.Text;
using Compiler.Analyser;
using Compiler.Text;
using LanguageExt;
using LanguageExt.UnsafeValueAccess;
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

                    if (!table.TryGetValue("ModuleName", out var moduleName)) throw new InvalidDataException("ModuleSpecification does not contain a 'ModuleName' key.");
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

    public static List<UsingStatementAst> FindDeclaredNamespaces(Ast ast) {
        var namespaces = new List<UsingStatementAst>();

        ast.FindAll(testAst => testAst is UsingStatementAst usingAst && usingAst.UsingStatementKind == UsingStatementKind.Namespace, true)
            .Cast<UsingStatementAst>()
            .ToList()
            .ForEach(namespaces.Add);

        return namespaces;
    }

    public static List<FunctionDefinitionAst> FindAvailableFunctions(Ast ast, bool onlyExported) {
        var allDefinedFunctions = ast
            .FindAll(testAst => testAst is FunctionDefinitionAst, true)
            .Cast<FunctionDefinitionAst>()
            .ToList();

        // Short circuit so we don't have to do any more work if we are not filtering for only exported functions.
        if (!onlyExported) return allDefinedFunctions;

        return [.. GetWantedExports(ast, "Function", allDefinedFunctions, function => NameWithoutNamespace(function.Name))];
    }

    public static IEnumerable<string> FindAvailableAliases(Ast ast, bool onlyExported) {
        var allAstFunctionCalls = ast
            .FindAll(testAst => testAst is CommandAst commandAst && commandAst.CommandElements[0].Extent.Text is "Set-Alias" or "New-Alias", true)
            .Cast<CommandAst>()
            .ToList();

        var allFunctionsWithAliases = ast
            .FindAll(testAst => testAst is FunctionDefinitionAst, true)
            .Cast<FunctionDefinitionAst>()
            .Where(function => function.Body.ParamBlock != null)
            .Where(functionDefinition => functionDefinition.Body.ParamBlock!.Attributes.Any(attribute => attribute.TypeName.GetReflectionType() == typeof(AliasAttribute)));

        var availableAliases = new List<string>();
        var attributeType = typeof(AliasAttribute);
        availableAliases.AddRange(allFunctionsWithAliases.SelectMany(function => function.Body.ParamBlock.Attributes
            .Where(attribute => attribute.TypeName.GetReflectionAttributeType() == attributeType)
            .SelectMany(attribute => {
                var aliasesObject = attribute.NamedArguments.FirstOrDefault(namedArg => namedArg.ArgumentName is "aliasNames")?.Argument
                    ?? attribute.PositionalArguments.FirstOrDefault();

                return aliasesObject switch {
                    ArrayLiteralAst arrayLiteralAst => arrayLiteralAst.Elements.Select(element => element.SafeGetValue()).Cast<string>(),
                    StringConstantExpressionAst stringConstantAst => [stringConstantAst.Value],
                    _ => [],
                };
            })
        ));

        availableAliases.AddRange(allAstFunctionCalls.SelectMany(static commandAst => commandAst.CommandElements
            .Where(static commandElement => commandElement is CommandParameterAst)
            .Cast<CommandParameterAst>()
            .Where(static param => param.ParameterName == "Name")
            .Select(param => {
                var value = param.Argument ?? commandAst.CommandElements[commandAst.CommandElements.IndexOf(param) + 1] as ExpressionAst;
                return value switch {
                    StringConstantExpressionAst stringConstantAst => stringConstantAst.Value,
                    _ => null
                };
            })
            .Where(static alias => !string.IsNullOrWhiteSpace(alias))
            .Cast<string>()
        // .Select(static ast => ast.Value)
        ));

        if (!onlyExported) return availableAliases;

        return GetWantedExports(ast, "Alias", availableAliases, NameWithoutNamespace);
    }

    private static IEnumerable<T> GetWantedExports<T>(Ast ast, string kind, IEnumerable<T> availableItems, Func<T, string> getName) {
        var exportCommands = ast.FindAll(testAst =>
            testAst is CommandAst commandAst && commandAst.CommandElements[0].Extent.Text == "Export-ModuleMember", true
        ).Cast<CommandAst>();

        // If there are no Export-ModuleMember commands, we are exporting everything.
        if (!exportCommands.Any()) {
            return availableItems;
        }

        var wantingToExport = new List<string>();
        foreach (var exportCommand in exportCommands) {
            // TODO - Support unnamed export param eg `Export-ModuleMember *`
            var namedParameters = exportCommand.CommandElements
                .Where(commandElement => commandElement is CommandParameterAst)
                .Cast<CommandParameterAst>()
                .Where(param => param.ParameterName.Equals(kind, StringComparison.OrdinalIgnoreCase));

            foreach (var namedParameter in namedParameters) {
                var value = namedParameter.Argument
                    ?? exportCommand.CommandElements[exportCommand.CommandElements.IndexOf(namedParameter) + 1] as ExpressionAst;

                var objects = value switch {
                    StringConstantExpressionAst starAst when starAst.Value == "*" => availableItems.Select(getName),
                    StringConstantExpressionAst stringConstantAst => [stringConstantAst.Value],
                    ArrayLiteralAst arrayLiteralAst => arrayLiteralAst.Elements.Select(element => element.SafeGetValue()),
                    _ => [], // We don't know what to do with this value, so we will just ignore it.
                };

                wantingToExport.AddRange(objects.Cast<string>());
            }
        }

        return availableItems.Where(item => wantingToExport.Contains(getName(item)));
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
    [return: NotNull]
    public static Fin<ScriptBlockAst> GetAstReportingErrors(
        [NotNull] string astContent,
        [NotNull] Option<string> filePath,
        [NotNull] IEnumerable<string> ignoredErrors,
        out Token[] tokens
    ) {
        ArgumentNullException.ThrowIfNull(astContent);
        ArgumentNullException.ThrowIfNull(filePath);
        ArgumentNullException.ThrowIfNull(ignoredErrors);

        var ast = Parser.ParseInput(astContent, filePath.ValueUnsafe(), out tokens, out var parserErrors);
        parserErrors = [.. parserErrors.Where(error => !ignoredErrors.Contains(error.ErrorId))];

        if (parserErrors.Length != 0) {
            var issues = parserErrors.Select(error => Issue.Error(error.Message, error.Extent, ast));
            var errors = Error.Many(issues.ToArray());
            return new WrappedErrorWithDebuggableContent(None, astContent, errors);
        }

        return ast;
    }

    // TODO - ability to translate the virtual cleaned line numbers to the actual line numbers in the file.
    [return: NotNull]
    public static string GetPrettyAstError(
        [NotNull] IScriptExtent extent,
        [NotNull] Ast parentAst,
        [NotNull] Option<string> message,
        [NotNull] Option<string> realFilePath = default,
        [NotNull] IssueSeverity severity = IssueSeverity.Error) {
        ArgumentNullException.ThrowIfNull(extent);
        ArgumentNullException.ThrowIfNull(parentAst);
        ArgumentNullException.ThrowIfNull(message);


        var problemColour = severity switch {
            IssueSeverity.Error => "#8b0000",
            IssueSeverity.Warning => "#f9f1a5",
            _ => "#808080"
        };

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
                0 when i == extentRegion.Length - 1 => string.Concat(line[0..startingColumn], line[startingColumn..endingColumn].Pastel(problemColour), line[endingColumn..]),
                0 => string.Concat(line[0..startingColumn], line[startingColumn..].Pastel(problemColour)),
                var _ when i == extentRegion.Length - 1 => string.Concat(line[0..endingColumn].Pastel(problemColour), line[endingColumn..]),
                _ => line.Pastel(problemColour)
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

        var fileName = realFilePath.UnwrapOrElse(() => parentAst.Extent.File is null ? "Unknown file" : parentAst.Extent.File);

        var location = TextSpan.New(startingLine, startingColumn, endingLine, endingColumn).Unwrap(); // Safety: Extents should always be valid.
        return $"""
        {"File".PadRight(firstColumnIndent).Pastel(ConsoleColor.Cyan)}{colouredPipe} {fileName.Pastel(ConsoleColor.Gray)}
        {"Where".PadRight(firstColumnIndent).Pastel(ConsoleColor.Cyan)}{colouredPipe} {location.ToString().Pastel(ConsoleColor.Gray)}
        {string.Join('\n', printableLines)}
        {firstColumnIndentString}{colouredPipe} {errorPointer.Pastel(problemColour)}
        {firstColumnIndentString}{colouredPipe} {message.UnwrapOrElse(static () => "Unknown Error").Pastel(problemColour)}
        """;
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

    [return: NotNull]
    private static string NameWithoutNamespace(string name) => name.Contains(':') ? name.Split(':').Last() : name;
}
