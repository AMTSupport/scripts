// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation.Language;
using LanguageExt;

namespace Compiler.Text.Updater;

public class AstUpdater(
    uint priority,
    Func<Ast, bool> astPredicate,
    Func<Ast, string[]> updater,
    UpdateOptions options) : TextSpanUpdater(priority) {
    public override Fin<SpanUpdateInfo[]> Apply(List<string> lines) => AstHelper.GetAstReportingErrors(string.Join('\n', lines), Some("AstUpdater"), ["ModuleNotFoundDuringParse"])
        .AndThen(ast => {
            IEnumerable<Ast> nodesToUpdate;
            if (options.HasFlag(UpdateOptions.MatchEntireDocument)) {
                nodesToUpdate = ast.FindAll(astPredicate, true);
                if (!nodesToUpdate.Any()) return FinSucc<SpanUpdateInfo[]>([]);
            } else {
                var node = ast.Find(astPredicate, true);
                if (node == null) return FinSucc<SpanUpdateInfo[]>([]);
                nodesToUpdate = [node];
            }

            var offset = 0;
            var updateSpans = new List<SpanUpdateInfo>();
            foreach (var node in nodesToUpdate) {
                var thisOffset = 0;
                var extent = node.Extent;
                var spanResult = TextSpan.New(
                    extent.StartLineNumber - 1,
                    extent.StartColumnNumber - 1,
                    extent.EndLineNumber - 1,
                    extent.EndColumnNumber - 1
                );
                if (spanResult.IsErr(out var err, out var span)) {
                    return FinFail<SpanUpdateInfo[]>(err);
                }

                var isMultiLine = span.StartingIndex != span.EndingIndex;
                var newContent = updater(node);
                ArgumentNullException.ThrowIfNull(newContent);

                // Remove the entire line if the replacement is empty and the match is the entire line.
                if (newContent == null && span.StartingColumn == 0 && span.EndingColumn == lines[span.StartingIndex].Length) {
                    thisOffset += span.RemoveContent(lines);
                } else {
                    thisOffset += span.SetContent(lines, options, newContent!);
                }

                updateSpans.Add(new SpanUpdateInfo(span, thisOffset));
                offset += thisOffset;
            }

            return updateSpans.ToArray();
        });
}
