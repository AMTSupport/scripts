// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics.CodeAnalysis;
using LanguageExt;

namespace Compiler.Text;

public record SpanUpdateInfo(
    [NotNull] TextSpanUpdater Updater,
    [NotNull] TextSpan TextSpan,
    [NotNull] ContentChange Change
) {
    public override string ToString() => $"[{this.TextSpan} + {this.TextSpan.StringifyOffset(this.Change)}]->{this.Updater}";
}

public abstract class TextSpanUpdater(uint priority = 50) : IComparable<TextSpanUpdater> {
    public readonly uint Priority = priority;

    /// <summary>
    /// Apply the update to the lines.
    /// </summary>
    /// <param name="lines">
    /// The lines of the document to apply the update to.
    /// </param>
    /// <returns>
    /// The number of lines changed by the update.
    /// </returns>
    public abstract Fin<IEnumerable<SpanUpdateInfo>> Apply(List<string> lines);

    /// <summary>
    /// Use informaiton from another update to possibly update this ones variables.
    /// This can be used to update the starting index of a span after a previous span has been removed.
    /// </summary>
    [ExcludeFromCodeCoverage(Justification = "This is a virtual method that may be overridden.")]
    public virtual void PushByUpdate(SpanUpdateInfo updateInfo) { /*Do Nothing*/ }

    public virtual int CompareTo(TextSpanUpdater? other) => other is null ? -1 : this.Priority.CompareTo(other.Priority);

    public override string ToString() => $"{this.GetType().Name}[{this.Priority}]";

    public override bool Equals(object? obj) {
        if (ReferenceEquals(this, obj)) return true;
        if (obj is null) return false;

        return obj is TextSpanUpdater updater && this.Priority == updater.Priority;
    }

    public override int GetHashCode() => this.Priority.GetHashCode();

    public static bool operator ==(TextSpanUpdater left, TextSpanUpdater right) => left is null ? right is null : left.Equals(right);

    public static bool operator !=(TextSpanUpdater left, TextSpanUpdater right) => !(left == right);

    public static bool operator <(TextSpanUpdater left, TextSpanUpdater right) => left is null ? right is not null : left.CompareTo(right) < 0;

    public static bool operator <=(TextSpanUpdater left, TextSpanUpdater right) => left is null || left.CompareTo(right) <= 0;

    public static bool operator >(TextSpanUpdater left, TextSpanUpdater right) => left is not null && left.CompareTo(right) > 0;

    public static bool operator >=(TextSpanUpdater left, TextSpanUpdater right) => left is null ? right is null : left.CompareTo(right) >= 0;
}
