using System.Management.Automation;
using System.Management.Automation.Language;
using System.Text.RegularExpressions;
using CommandLine;
using Compiler.Requirements;
using Text;

namespace Compiler.Module;

public partial class LocalFileModule : Module
{
    public readonly TextEditor Document;
    protected readonly ScriptBlockAst Ast;

    public LocalFileModule(string name, string[] lines) : base(new ModuleSpec(name))
    {
        Document = new(new TextDocument(lines));

        Ast = GetAstReportingErrors(string.Join('\n', lines));

        AstHelper.FindDeclaredModules(Ast).ToList().ForEach(module =>
        {
            Requirements.AddRequirement(new ModuleSpec(
                Name: module.Key,
                Guid: module.Value.TryGetValue("Guid", out object? value) ? Guid.Parse(value.Cast<string>()) : null,
                MinimumVersion: module.Value.TryGetValue("MinimumVersion", out object? minimumVersion) ? Version.Parse(minimumVersion.Cast<string>()) : null,
                MaximumVersion: module.Value.TryGetValue("MaximumVersion", out object? maximumVersion) ? Version.Parse(maximumVersion.Cast<string>()) : null,
                RequiredVersion: module.Value.TryGetValue("RequiredVersion", out object? requiredVersion) ? Version.Parse(requiredVersion.Cast<string>()) : null
            ));
        });

        foreach (var match in lines.SelectMany(line => RequiresStatementRegex().Matches(line).Cast<Match>()))
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
                    Console.Error.WriteLine($"Not sure what to do with unexpected type: {type}, skipping.");
                    break;
            };
        }

        // Cleanup must be done after AST
        FixAndCleanLines();

        // Check the AST for any issues that have been introduced by the cleanup.
        GetAstReportingErrors(string.Join('\n', lines));
    }

    private static ScriptBlockAst GetAstReportingErrors(string astContent)
    {
        var ast = System.Management.Automation.Language.Parser.ParseInput(astContent, out _, out ParseError[] ParserErrors);

        ParserErrors = [.. ParserErrors.ToList().FindAll(error => !error.ErrorId.Equals("ModuleNotFoundDuringParse"))];
        if (ParserErrors.Length > 0)
        {
            Console.WriteLine("There was an issue trying to parse the script.");
            throw new ParseException(ParserErrors);
        }

        return ast;
    }

    private void FixAndCleanLines()
    {
        // Fix indentation for Multiline Strings
        Document.AddPatternEdit(
            @"^.*@[""']",
            @"^\s+.*[""']@",
            (lines) =>
            {
                var startIndex = 0;

                // If the multiline is not at the start of the content it does not need to be trimmed, so we skip it.
                var trimmedLine = lines[0].Trim();
                if (trimmedLine.StartsWith(@"@""") || trimmedLine.StartsWith("@'"))
                {
                    startIndex++;
                }

                // Get the multiline indent level from the last line of the string.
                // This is used so we don't remove any whitespace that is part of the actual string formatting.
                var indentLevel = BeginingWhitespaceMatchRegex().Match(lines.Last()).Value.Length;

                var updatedLines = lines.Select((line, index) =>
                {
                    if (index < startIndex)
                    {
                        return line;
                    }

                    return line[indentLevel..];
                });

                return updatedLines.ToArray();
            });


        // Document Blocks
        Document.AddPatternEdit(
            @"^\s*<#",
            @"^\s*#>",
            (lines) => { return []; });

        // Entire Line Comments
        Document.AddRegexEdit(@"^\s*#.*$", _ => { return string.Empty; });

        // Comments at the end of a line, after some code.
        Document.AddRegexEdit(@"\s*#.*$", _ => { return string.Empty; });

        // Remove empty lines
        Document.AddRegexEdit(@"^\s*$", _ => { return string.Empty; });
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

    public static LocalFileModule FromFile(string path)
    {
        return new LocalFileModule(path, File.ReadAllLines(path));
    }

    [GeneratedRegex(@"^\s*#Requires -(?<type>[A-Z]+) (?<value>.+)$")]
    private static partial Regex RequiresStatementRegex();

    [GeneratedRegex(@"^\s*")]
    private static partial Regex BeginingWhitespaceMatchRegex();

    public override string GetContent(int indent = 0)
    {
        var indentStr = new string(' ', indent);
        return $$"""
        {
        {{Document.GetContent(indent + 4)}}
        {{indentStr}}}
        """;
    }
}
