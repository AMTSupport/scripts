// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation.Language;

namespace Compiler.Text.Updater;

public class AstUpdater(
    uint priority,
    Func<Ast, bool> astPredicate,
    Func<Ast, string[]> updater,
        var ast = AstHelper.GetAstReportingErrors(string.Join('\n', lines), "AstUpdater", []);
    UpdateOptions options) : TextSpanUpdater(priority) {
    public override SpanUpdateInfo[] Apply(ref List<string> lines) {
        if (ast == null || string.IsNullOrWhiteSpace(ast.Extent.Text)) return [];

        IEnumerable<Ast> nodesToUpdate;
        if (options.HasFlag(UpdateOptions.MatchEntireDocument)) {
            nodesToUpdate = ast.FindAll(astPredicate, true);
            if (!nodesToUpdate.Any()) return [];
        } else {
            var node = ast.Find(astPredicate, true);
            if (node == null) return [];
            nodesToUpdate = [node];
        }

        var offset = 0;
        var updateSpans = new List<SpanUpdateInfo>();
        foreach (var node in nodesToUpdate) {
            var thisOffset = 0;
            var extent = node.Extent;
            var span = new TextSpan(
                extent.StartLineNumber - 1,
                extent.StartColumnNumber - 1,
                extent.EndLineNumber - 1,
                extent.EndColumnNumber - 1
            );

            var isMultiLine = span.StartingIndex != span.EndingIndex;
            var newContent = updater(node);
            ArgumentNullException.ThrowIfNull(newContent);

            // Remove the entire line if the replacement is empty and the match is the entire line.
            if (newContent == null && span.StartingColumn == 0 && span.EndingColumn == lines[span.StartingIndex].Length) { thisOffset += span.RemoveContent(ref lines); } else { thisOffset += span.SetContent(ref lines, options, newContent!); }

            updateSpans.Add(new SpanUpdateInfo(span, thisOffset));
            offset += thisOffset;
        }

        return [.. updateSpans];
    }
}
