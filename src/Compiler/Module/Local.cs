using System.Management.Automation;
using System.Management.Automation.Language;
using System.Text.RegularExpressions;
using CommandLine;
using Compiler.Requirements;
using Compiler.Text;
using NLog;

namespace Compiler.Module;

public partial class LocalFileModule : Module
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    protected readonly ScriptBlockAst Ast;
    public readonly TextEditor Document;
    public readonly string FilePath;


    public LocalFileModule(string path) : this(
        path,
        new ModuleSpec(Path.GetFileNameWithoutExtension(path)),
        new TextDocument(File.ReadAllLines(path))
    )
    { }

    public LocalFileModule(
        string path,
        ModuleSpec moduleSpec,
        TextDocument document,
        bool skipAstErrors = false,
        bool skipCleanup = false
    ) : base(moduleSpec)
    {
        FilePath = path;
        Document = new TextEditor(document);
        Ast = GetAstReportingErrors(string.Join('\n', Document.Document.Lines), skipAstErrors);

        ResolveRequirements();
        ResolveUsingStatements();

        if (skipCleanup)
        {
            return;
        }

        CompressLines();
        FixLines();

        // Check the AST for any issues that have been introduced by the cleanup.
        GetAstReportingErrors(string.Join('\n', Document.Document.Lines), skipAstErrors);
    }

    private static ScriptBlockAst GetAstReportingErrors(string astContent, bool ignoreErrors = false)
    {
        var ast = System.Management.Automation.Language.Parser.ParseInput(astContent, out _, out ParseError[] ParserErrors);

        ParserErrors = [.. ParserErrors.ToList().FindAll(error => !error.ErrorId.Equals("ModuleNotFoundDuringParse"))];
        if (!ignoreErrors && ParserErrors.Length > 0)
        {
            Console.WriteLine("There was an issue trying to parse the script.");
            throw new ParseException(ParserErrors);
        }

        return ast;
    }

    private void CompressLines()
    {
        // Remove empty lines
        Document.AddRegexEdit(EntireEmptyLineRegex(), _ => { return null; });

        // Document Blocks
        Document.AddPatternEdit(
            DocumentationStartRegex(),
            DocumentationEndRegex(),
            (lines) => { return []; });

        // Entire Line Comments
        Document.AddRegexEdit(EntireLineCommentRegex(), _ => { return null; });

        // Comments at the end of a line, after some code.
        Document.AddRegexEdit(EndOfLineComment(), _ => { return null; });
    }

    public void FixLines()
    {
        // Fix indentation for Multiline Strings
        Document.AddPatternEdit(
            MultilineStringOpenRegex(),
            MultilineStringCloseRegex(),
            (lines) =>
            {
                // Get the multiline indent level from the last line of the string.
                // This is used so we don't remove any whitespace that is part of the actual string formatting.
                var indentLevel = BeginingWhitespaceMatchRegex().Match(lines.Last()).Value.Length;
                var updatedLines = lines.Select((line, index) =>
                {
                    if (index < 1 || string.IsNullOrWhiteSpace(line))
                    {
                        return line;
                    }

                    return line[indentLevel..];
                });

                return updatedLines.ToArray();
            });
    }

    private void ResolveRequirements()
    {
        foreach (var match in Document.Document.Lines.SelectMany(line => RequiresStatementRegex().Matches(line).Cast<Match>()))
        {
            var type = match.Groups["type"].Value;
            // C# Switch statements are fucking grose.
            switch (type)
            {
                case "Version":
                    var parsedVersion = Version.Parse(match.Groups["value"].Value)!;
                    Requirements.AddRequirement(new PSVersionRequirement(parsedVersion));
                    break;
                case "Modules":
                    var modules = match.Groups["value"].Value.Split(',').Select(v => v.Trim()).ToArray();
                    foreach (var module in modules)
                    {
                        Requirements.AddRequirement(new ModuleSpec(
                            Name: module
                        ));
                    }

                    break;
                default:
                    Logger.Error($"Not sure what to do with unexpected type: {type}, skipping.");
                    break;
            };
        }
    }

    private void ResolveUsingStatements()
    {
        AstHelper.FindDeclaredModules(Ast).ToList().ForEach(module =>
        {
            Requirements.AddRequirement(new ModuleSpec(
                Name: module.Key,
                Guid: module.Value.TryGetValue("Guid", out object? value) ? Guid.Parse(value.Cast<string>()) : null,
                MinimumVersion: module.Value.TryGetValue("MinimumVersion", out object? minimumVersion) ? Version.Parse(minimumVersion.Cast<string>()) : null,
                MaximumVersion: module.Value.TryGetValue("MaximumVersion", out object? maximumVersion) ? Version.Parse(maximumVersion.Cast<string>()) : null,
                RequiredVersion: module.Value.TryGetValue("RequiredVersion", out object? requiredVersion) ? Version.Parse(requiredVersion.Cast<string>()) : null
            ));

            if (module.Value.TryGetValue("AST", out object? obj) && obj is UsingStatementAst ast)
            {
                // TODO - Remove the ; if it is at the end of the line
                Document.AddExactEdit(
                    ast.Extent.StartLineNumber - 1,
                    ast.Extent.StartColumnNumber - 1,
                    ast.Extent.EndLineNumber - 1,
                    ast.Extent.EndColumnNumber - 1,
                    lines => []
                );
            }
        });

        AstHelper.FindDeclaredNamespaces(Ast).ToList().ForEach(statement =>
        {
            var ns = statement.Item1;
            var ast = statement.Item2;

            Requirements.AddRequirement(new UsingNamespace(ns));
            // TODO - Remove the ; if it is at the end of the line
            Document.AddExactEdit(
                ast.Extent.StartLineNumber - 1,
                ast.Extent.StartColumnNumber - 1,
                ast.Extent.EndLineNumber - 1,
                ast.Extent.EndColumnNumber - 1,
                lines => []
            );
        });
    }

    public override ModuleMatch GetModuleMatchFor(ModuleSpec requirement)
    {
        // Local files have nothing but a name.
        if (ModuleSpec.Name == requirement.Name)
        {
            return ModuleMatch.Same;
        }

        return ModuleMatch.None;
    }

    public static LocalFileModule? TryFromFile(string relativeFrom, string path)
    {
        var fullPath = Path.GetFullPath(Path.Combine(relativeFrom, path));
        Logger.Debug($"Trying to load local file: {fullPath}");
        if (!File.Exists(fullPath))
        {
            Logger.Debug($"File does not exist: {fullPath}");
            return null;
        }

        return new LocalFileModule(fullPath);
    }

    public override string GetContent(int indent = 0)
    {
        var compiled = CompiledDocument.FromBuilder(Document, indent + 4);
        var indentStr = new string(' ', indent);
        return $$"""
        <#ps1#> @'
        {{compiled.GetContent()}}
        {{indentStr}}
        '@
        """;
    }

    [GeneratedRegex(@"^\s*#Requires -(?<type>[A-Z]+) (?<value>.+)$")]
    private static partial Regex RequiresStatementRegex();

    [GeneratedRegex(@"^\s*")]
    private static partial Regex BeginingWhitespaceMatchRegex();
    [GeneratedRegex(@"^(?!\n)*$")]
    public static partial Regex EntireEmptyLineRegex();

    [GeneratedRegex(@"^(?!\n)\s*<#")]
    public static partial Regex DocumentationStartRegex();

    [GeneratedRegex(@"^(?!\n)\s*#>")]
    public static partial Regex DocumentationEndRegex();

    [GeneratedRegex(@"^(?!\n)\s*#.*$")]
    public static partial Regex EntireLineCommentRegex();

    [GeneratedRegex(@"(?!\n)\s*(?<!<)#(?!>).*$")]
    public static partial Regex EndOfLineComment();

    [GeneratedRegex(@"^.*@[""']")]
    public static partial Regex MultilineStringOpenRegex();

    [GeneratedRegex(@"^\s*[""']@")]
    public static partial Regex MultilineStringCloseRegex();
}
