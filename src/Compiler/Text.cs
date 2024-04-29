public class TextDocument
{
    public string[] Lines { get; set; }

    public TextDocument(string[] lines)
    {
        Lines = lines;
    }
}

public class TextSpan
{
    public int StartingIndex { get; }
    public int StartingColumn { get; }
    public int EndingIndex { get; }
    public int EndingColumn { get; }

    public TextSpan(int startingIndex, int startingColumn, int endingIndex, int endingColumn)
    {
        StartingIndex = startingIndex;
        StartingColumn = startingColumn;
        EndingIndex = endingIndex;
        EndingColumn = endingColumn;
    }

    public bool Contains(int index, int column)
    {
        if (index < StartingIndex || index > EndingIndex)
        {
            return false;
        }

        if (index == StartingIndex && column < StartingColumn)
        {
            return false;
        }

        if (index == EndingIndex && column > EndingColumn)
        {
            return false;
        }

        return true;
    }

    public string GetContent(string[] lines)
    {
        if (StartingIndex == EndingIndex)
        {
            return lines[StartingIndex].Substring(StartingColumn, EndingColumn - StartingColumn);
        }

        string content = lines[StartingIndex].Substring(StartingColumn);
        for (int i = StartingIndex + 1; i < EndingIndex; i++)
        {
            content += lines[i];
        }

        content += lines[EndingIndex].Substring(0, EndingColumn);
        return content;
    }

    public void SetContent(string[] lines, string content)
    {
        if (StartingIndex == EndingIndex)
        {
            lines[StartingIndex] = lines[StartingIndex].Substring(0, StartingColumn) + content + lines[StartingIndex].Substring(EndingColumn);
            return;
        }

        lines[StartingIndex] = lines[StartingIndex].Substring(0, StartingColumn) + content;
        for (int i = StartingIndex + 1; i < EndingIndex; i++)
        {
            lines[i] = string.Empty;
        }

        lines[EndingIndex] = lines[EndingIndex].Substring(EndingColumn);
    }
}

public class TextSpanUpdater
{
    public TextSpan TextSpan { get; }
    public Func<string[]> CreateNewLines { get; }

    public TextSpanUpdater(int startingIndex, int endingIndex, Func<string[]> createNewLines)
    {
        TextSpan = new TextSpan(startingIndex, 0, endingIndex, 0);
        CreateNewLines = createNewLines;
    }
}

public class TextEditor
{
    public TextDocument Document { get; set; }
    public List<TextSpanUpdater> RangeEdits { get; set; }
    public bool EditApplied { get; set; }

    public TextEditor(TextDocument document)
    {
        Document = document;
        RangeEdits = new List<TextSpanUpdater>();
        EditApplied = false;
    }

    public void AddRangeEdit(int startingIndex, int endingIndex, Func<string[]> createNewLines)
    {
        VerifyAppliedOrError();

        var rangeEdit = new TextSpanUpdater(startingIndex, endingIndex, createNewLines);
        RangeEdits.Add(rangeEdit);
    }

    public void ApplyRangeEdits()
    {
        VerifyAppliedOrError();
        // Implementation of ApplyRangeEdits method
    }

    public string GetContent()
    {
        if (!EditApplied)
        {
            throw new Exception("Cannot get content from a document that has not had its edits applied.");
        }

        return string.Join(Environment.NewLine, Document.Lines);
    }

    private void VerifyAppliedOrError()
    {
        if (!EditApplied)
        {
            throw new Exception("Cannot add a range edit to a document that has not has its edits applied.");
        }
    }
}
