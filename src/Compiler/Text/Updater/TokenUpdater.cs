// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation.Language;
using LanguageExt;

namespace Compiler.Text.Updater;

public class TokenUpdater(
    uint priority,
    Func<Token, bool> predicate,
    Func<Token, string[]> updater,
    UpdateOptions options
) : NodeEnumerableUpdater<Token>(priority, predicate, updater, options) {
    public override Fin<IEnumerable<Token>> GetUpdatableNodes(List<string> lines, Func<Token, bool> predicate, UpdateOptions options) {
        AstHelper.GetAstReportingErrors(string.Join('\n', lines), Some("TokenUpdater"), ["ModuleNotFoundDuringParse"], out var tokens);
        return FinSucc(tokens.Where(predicate));
    }

    public override Fin<TextSpan> GetSpan(Token token) => TextSpan.New(
        token.Extent.StartLineNumber - 1,
        token.Extent.StartColumnNumber - 1,
        token.Extent.EndLineNumber - 1,
        token.Extent.EndColumnNumber - 1
    );
}
