// Copyright (c) 2024 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Management.Automation.Language;
using LanguageExt;

namespace Compiler.Text.Updater;

public class AstUpdater(
    uint priority,
    Func<Ast, bool> predicate,
    Func<Ast, string[]> updater,
    UpdateOptions options
) : NodeEnumerableUpdater<Ast>(priority, predicate, updater, options) {
    public override Fin<IEnumerable<Ast>> GetUpdatableNodes(List<string> lines, Func<Ast, bool> predicate, UpdateOptions options) => AstHelper.GetAstReportingErrors(string.Join('\n', lines), Some("AstUpdater"), ["ModuleNotFoundDuringParse"], out _)
        .AndThen(ast => {
            IEnumerable<Ast> nodesToUpdate;
            if (options.HasFlag(UpdateOptions.MatchEntireDocument)) {
                nodesToUpdate = ast.FindAll(predicate, true);
            } else {
                var node = ast.Find(predicate, true);
                if (node == null) return [];
                nodesToUpdate = [node];
            }

            return nodesToUpdate;
        });

    public override Fin<TextSpan> GetSpan(Ast item) => TextSpan.New(
        item.Extent.StartLineNumber - 1,
        item.Extent.StartColumnNumber - 1,
        item.Extent.EndLineNumber - 1,
        item.Extent.EndColumnNumber - 1
    );
}
