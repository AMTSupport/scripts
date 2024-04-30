using System.Management.Automation;
using System.Management.Automation.Language;
using System.Text.RegularExpressions;
using CommandLine;
using Text;

namespace Compiler
{
    public class Module : TextEditor
    {
        public string Name { get; }
        public Requirements Requirements { get; }
        // public Dictionary<string, Module> InnerModules { get; }
        private string[] Lines { get; }
        private List<TextEditor> TextRanges { get; }
        private readonly ScriptBlockAst Ast;

        public Module(string name, string[] lines) : base(new TextDocument(lines))
        {
            Name = name;
            Lines = lines;
            EditApplied = false;
            Requirements = new Requirements();
            TextRanges = [];

            Ast = System.Management.Automation.Language.Parser.ParseInput(string.Join("\n", Lines), out _, out ParseError[] ParserErrors);
            if (ParserErrors.Length > 0)
            {
                throw new ParseException(ParserErrors);
            }

            AstHelper.FindDeclaredModules(Ast).ToList().ForEach(module =>
            {
                Requirements.AddRequirement(new ModuleRequirement(
                    name: module.Key,
                    guid: module.Value.TryGetValue("Guid", out object? value) ? Guid.Parse(value.Cast<string>()) : null,
                    mimimumVersion: module.Value.TryGetValue("MinimumVersion", out object? minimumVersion) ? Version.Parse(minimumVersion.Cast<string>()) : null,
                    maximumVersion: module.Value.TryGetValue("MaximumVersion", out object? maximumVersion) ? Version.Parse(maximumVersion.Cast<string>()) : null,
                    requiredVersion: module.Value.TryGetValue("RequiredVersion", out object? requiredVersion) ? Version.Parse(requiredVersion.Cast<string>()) : null
                ));
            });

            foreach (var match in Lines.SelectMany(line => Regex.Matches(line, @"^\s*#Requires -(?<type>[A-Z]+) (?<value>.+)$").Cast<Match>()))
            {
                var type = match.Groups["type"].Value;
                // C# Switch statements are fucking grose.
                switch (type)
                {
                    case "Version":
                        var parsedVersion = Version.Parse(match.Groups["value"].Value)!;
                        Requirements.AddRequirement(new VersionRequirement(parsedVersion));
                        break;
                    case "Modules":
                        var modules = match.Groups["value"].Value.Split(',').Select(v => v.Trim()).ToArray();
                        foreach (var module in modules)
                        {
                            Requirements.AddRequirement(new ModuleRequirement(
                                name: module
                            ));
                        }

                        break;
                    default:
                        Console.Error.WriteLine($"Not sure what to do with unexpected type: {type}, skipping.");
                        break;
                };
            }
        }
    }
}
