namespace Compiler.Text.Updater;

public class IndentUpdater(int indentBy) : TextSpanUpdater(70)
{
    private readonly int IndentBy = indentBy;

    public override SpanUpdateInfo[] Apply(ref List<string> lines)
    {
        var updateSpans = new List<SpanUpdateInfo>();
        var indentString = new string(' ', IndentBy);
        for (var i = 0; i < lines.Count; i++)
        {
            // Don't indent empty lines.
            if (lines[i].Length == 0)
            {
                continue;
            }

            lines[i] = $"{indentString}{lines[i]}";
            updateSpans.Add(new SpanUpdateInfo(new(i, i, 0, 0), 4));
        }

        return [.. updateSpans];
    }
}
