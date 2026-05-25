// Copyright (c) 2024 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using LanguageExt;

namespace Compiler.Text.Updater.Built;

public class IndentUpdater(int indentBy) : TextSpanUpdater(70) {
    private readonly int IndentBy = indentBy;

    public override Fin<IEnumerable<SpanUpdateInfo>> Apply(List<string> lines) {
        var updateSpans = new List<SpanUpdateInfo>();
        var indentString = new string(' ', this.IndentBy);
        for (var i = 0; i < lines.Count; i++) {
            // Don't indent empty lines.
            if (lines[i].Length == 0) continue;

            lines[i] = $"{indentString}{lines[i]}";
            var spanResult = TextSpan.New(i, 0, i, 0);
            if (spanResult.IsErr(out var err, out var span)) return err;

            var change = new ContentChange(0, this.IndentBy, 0);
            updateSpans.Add(new SpanUpdateInfo(this, span, change));
        }

        return updateSpans;
    }
}
