using System.Diagnostics.CodeAnalysis;
using Compiler.Text.Updater;

namespace Compiler.Text;

public record SpanUpdateInfo(
    TextSpan TextSpan,
    int Offset)
{
    public override string ToString() => $"{nameof(PatternUpdater)}({TextSpan} +- {Offset})";
}

public abstract class TextSpanUpdater(uint priority = 50)
{
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
    public abstract SpanUpdateInfo[] Apply(ref List<string> lines);

    /// <summary>
    /// Use informaiton from another update to possibly update this ones variables.
    /// This can be used to update the starting index of a span after a previous span has been removed.
    /// </summary>
    [ExcludeFromCodeCoverage(Justification = "This is a virtual method that may be overridden.")]
    public virtual void PushByUpdate(SpanUpdateInfo updateInfo) { /*Do Nothing*/ }
}
