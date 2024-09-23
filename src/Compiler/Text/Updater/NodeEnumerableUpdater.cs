// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using LanguageExt;

namespace Compiler.Text.Updater;

public abstract class NodeEnumerableUpdater<TItem>(
    uint priority,
    Func<TItem, bool> itemPredicate,
    Func<TItem, string[]> itemUpdater,
    UpdateOptions options
) : TextSpanUpdater(priority) {
    public abstract Fin<IEnumerable<TItem>> GetUpdatableNodes(List<string> lines, Func<TItem, bool> predicate, UpdateOptions options);

    public abstract Fin<TextSpan> GetSpan(TItem item);

    public override Fin<IEnumerable<SpanUpdateInfo>> Apply(List<string> lines) {
        var nodesResult = this.GetUpdatableNodes(lines, itemPredicate, options);
        if (nodesResult.IsErr(out var err, out var nodes)) return err;
        if (!nodes.Any()) return System.Array.Empty<SpanUpdateInfo>();

        var updateSpans = new List<SpanUpdateInfo>();
        foreach (var node in nodes) {
            Fin<ContentChange> thisChange;
            if (this.GetSpan(node).IsErr(out err, out var span)) return err;
            span = span.WithUpdate(updateSpans);

            var isMultiLine = span.StartingIndex != span.EndingIndex;
            var newContent = itemUpdater(node);

            // Remove the entire line if the replacement is empty and the match is the entire line.
            thisChange = newContent.Length == 0 && span.StartingColumn == 0 && span.EndingColumn == lines[span.StartingIndex].Length
                ? span.RemoveContent(lines)
                : span.SetContent(lines, options, newContent!);

            if (thisChange.IsErr(out err, out var change)) return err;

            updateSpans.Add(new SpanUpdateInfo(this, span, change));
        }

        return updateSpans.ToArray();
    }
}
