// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation.Language;
using LanguageExt;

namespace Compiler.Text.Updater.Built;

/// <summary>
/// Removes all empty lines, including lines that only contain whitespace, unless they are within a string.
///
/// Additionally will remove any whitespace at the end of a line.
/// </summary>
public sealed class WhitespaceUpdater() : TextSpanUpdater(90) {
    public override Fin<IEnumerable<SpanUpdateInfo>> Apply(List<string> lines) {
        // Remove all empty lines, including lines that only contain whitespace, unless they are within a string.
        if (AstHelper.GetAstReportingErrors(string.Join('\n', lines), None, ["ModuleNotFoundDuringParse"], out _).IsErr(out var err, out var ast)) {
            return err;
        }

        var stringConstants = ast.FindAll(x => x is StringConstantExpressionAst ast && ast.StringConstantType is StringConstantType.SingleQuotedHereString or StringConstantType.DoubleQuotedHereString, true)
            .Select(x => TextSpan.New(x.Extent.StartLineNumber - 1, x.Extent.StartColumnNumber - 1, x.Extent.EndLineNumber - 1, x.Extent.EndColumnNumber - 1).Unwrap())
            .ToList();

        var lineCount = lines.Count;
        var spanUpdates = new List<SpanUpdateInfo>();
        for (var i = 0; i < lineCount; i++) {
            var line = lines[i + spanUpdates.Aggregate(0, (acc, x) => acc + x.Change.LineOffset)];

            TextSpan? span = null;
            if (string.IsNullOrWhiteSpace(line)) {
                span = TextSpan.New(i, 0, i, line.Length)
                    .Unwrap() // Safe to unwrap here as we know the span is valid
                    .WithUpdate(spanUpdates);
            } else {
                var whitespaceCount = line.Reverse().TakeWhile(char.IsWhiteSpace).Count();
                if (whitespaceCount > 0) {
                    span = TextSpan.New(i, line.Length - whitespaceCount, i, line.Length)
                        .Unwrap() // Safe to unwrap here as we know the span is valid
                        .WithUpdate(spanUpdates);
                }
            }

            if (span == null) continue;

            var intersectingNode = stringConstants.Find(x => x.Contains(span));
            if (intersectingNode != null) continue;

            if (span.SetContent(lines, UpdateOptions.None, []).IsErr(out err, out var contentChange)) {
                return err;
            }

            spanUpdates.Add(new SpanUpdateInfo(this, span, contentChange));
            stringConstants = stringConstants
                .Where(x => x.EndingIndex >= span.EndingIndex) // Remove any contants that are before the current span as they are no longer relevant
                .Select(x => x.WithUpdate(spanUpdates)).ToList();
        }

        return spanUpdates;
    }
}
