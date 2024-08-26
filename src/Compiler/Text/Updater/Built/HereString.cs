// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics.CodeAnalysis;
using System.Diagnostics.Contracts;
using System.Management.Automation.Language;

namespace Compiler.Text.Updater.Built;

public partial class HereStringUpdater() : AstUpdater(
    80,
    static ast => ast is StringConstantExpressionAst stringConstantAst && stringConstantAst.StringConstantType is StringConstantType.SingleQuotedHereString or StringConstantType.DoubleQuotedHereString,
    static hereString => InternalApply(hereString),
    UpdateOptions.InsertInline
) {
    [Pure]
    public static string[] InternalApply([NotNull] Ast ast) {
        ArgumentNullException.ThrowIfNull(ast);
        if (ast is not StringConstantExpressionAst stringConstant) return [];

        var linesAfterMaybeUpdate = stringConstant.StringConstantType switch {
            StringConstantType.SingleQuotedHereString => UpdateTerminators(stringConstant),
            StringConstantType.DoubleQuotedHereString => stringConstant.Extent.Text.Split('\n'),
            // This should never happen, but if it does, throw an exception.
            _ => throw new NotImplementedException($"Unsupported string constant type: {stringConstant.StringConstantType}")
        };

        return UpdateIndentation(linesAfterMaybeUpdate);
    }

    /// <summary>
    /// Removes the indentation from the multiline string.
    ///
    /// This is done by finding how much whitespace is present on the terminating line,
    /// and then removing that amount of whitespace from every line in the string.
    /// </summary>
    /// <param name="lines">
    /// The lines of the multiline string.
    /// </param>
    /// <returns>
    /// An array of strings with the indentation removed.
    /// </returns>
    [Pure]
    internal static string[] UpdateIndentation([NotNull] IEnumerable<string> lines) {
        // Get the multiline indent level from the last line of the string.
        // This is used so we don't remove any whitespace that is part of the actual string formatting.
        var indentLevel = lines.Last().TakeWhile(char.IsWhiteSpace).Count();
        var updatedLines = lines.Select((line, index) => {
            if (index < 1 || string.IsNullOrWhiteSpace(line)) {
                return line;
            }

            return line[indentLevel..];
        });

        return updatedLines.ToArray();
    }

    /// <summary>
    /// Updates the terminators of a here-string.
    ///
    /// This is done by returning a string with the exact same content,
    /// but with double quoted terminators.
    /// </summary>
    /// <param name="ast">
    /// The here-string to update.
    /// </param>
    /// <returns>
    /// A string with the same content as the AST, but with double quoted terminators.
    /// </returns>
    [Pure]
    internal static string[] UpdateTerminators([NotNull] StringConstantExpressionAst stringConstant) {
        ArgumentNullException.ThrowIfNull(stringConstant);

        return ["@\"", stringConstant.Value, "\"@"];
    }
}
