using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Language;
using System.Text.RegularExpressions;

public class Module : TextEditor
{
    public string Name { get; }
    public Dictionary<string, object> Requirements { get; }
    private string[] Lines { get; }
    private List<TextEditor> TextRanges { get; }
    private ScriptBlockAst Ast;

    public Module(string name, string[] lines) : base(new TextDocument(lines))
    {
        Name = name;
        Lines = lines;
        EditApplied = false;

        Ast = Parser.ParseInput(string.Join("\n", Lines), out _, out ParseError[] ParserErrors);
        if (ParserErrors.Length > 0)
        {
            throw new ParseException(ParserErrors);
        }

        Requirements = new Dictionary<string, object> {
            { "Version", null },
            { "Modules", AstHelepr.FindDeclaredModules(Ast) }
        };

        foreach (var match in Lines.SelectMany(line => Regex.Matches(line, @"^\s*#Requires -(?<type>[A-Z]+) (?<value>.+)$").Cast<Match>()))
        {
            var type = match.Groups["type"].Value;
            var value = type == "Modules" ? (object)match.Groups["value"].Value.Split(',').Select(v => v.Trim()).ToArray() : match.Groups["value"].Value.Trim();

            if (Requirements.ContainsKey(type))
            {
                ((List<string>)Requirements[type]).Add(value);
            }
            else
            {
                Requirements.Add(type, new List<string> { value });
            }
        }

        var requirementsTable = new Dictionary<string, object>();
        foreach (var requirement in Requirements)
        {
            var uniqueValues = ((List<string>)requirement.Value).Distinct().ToList();
            var selectedValue = requirement.Key == "Version" ? uniqueValues.Select(v => Version.Parse(v)).OrderByDescending(v => v).First() : (object)uniqueValues;
            requirementsTable.Add(requirement.Key, selectedValue);
        }
    }

    public void AddRegexEdit(string startingPattern, string endingPattern, Func<string[]> createNewLines)
    {
        if (EditApplied)
        {
            throw new Exception("Cannot add a regex edit to a module that has already been applied.");
        }

        while (true)
        {
            var (startIndex, endIndex) = AstHelepr.FindStartToEndBlock(Lines, startingPattern, endingPattern);
            if (startIndex == -1 || endIndex == -1)
            {
                break;
            }

            var rangeEdit = new TextSpanUpdater(startIndex, endIndex, createNewLines);
            RangeEdits.Add(rangeEdit);
        }
    }
}
