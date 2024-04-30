using System.Text.RegularExpressions;
using Compiler;

class CompiledScript : Module
{
    public CompiledScript(string name, string[] lines) : base(name, lines)
    {
        // Multiline Strings
        AddPatternEdit(
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
                var indentLevel = Regex.Match(lines.Last(), @"^\s*").Value.Length;

                var updatedLines = lines.Select((line, index) =>
                {
                    if (index < startIndex)
                    {
                        return line;
                    }

                    return line.Substring(indentLevel);
                });

                return updatedLines.ToArray();
            });


        // Document Blocks
        AddPatternEdit(
            @"^.*@[""']",
            @"^\s+.*[""']@",
            (lines) => { return []; });

        // Entire Line Comments
        AddRegexEdit(@"^\s*#.*$", _ => { return string.Empty; });

        // Comments at the end of a line, after some code.
        AddRegexEdit(@"\s*#.*$", _ => { return string.Empty; });

        // Remove empty lines
        AddRegexEdit(@"^\s*$", _ => { return string.Empty; });
    }
}
