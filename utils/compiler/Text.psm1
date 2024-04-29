class TextDocument {
    [String[]]$Lines;

    TextDocument(
        [String[]]$Lines
    ) {
        $this.Lines = $Lines;
    }
}

class TextSpan {
    [Int]$StartingIndex;
    [Int]$StartingColumn;

    [Int]$EndingIndex;
    [Int]$EndingColumn;

    TextSpan(
        [Int]$StartingIndex,
        [Int]$StartingColumn,
        [Int]$EndingIndex,
        [Int]$EndingColumn
    ) {
        $this.StartingIndex = $StartingIndex;
        $this.StartingColumn = $StartingColumn;
        $this.EndingIndex = $EndingIndex;
        $this.EndingColumn = $EndingColumn;
    }

    [Boolean] Contains(
        [Int]$Index,
        [Int]$Column
    ) {
        if ($Index -lt $this.StartingIndex -or $Index -gt $this.EndingIndex) {
            return $False;
        }

        if ($Index -eq $this.StartingIndex -and $Column -lt $this.StartingColumn) {
            return $False;
        }

        if ($Index -eq $this.EndingIndex -and $Column -gt $this.EndingColumn) {
            return $False;
        }

        return $True;
    }

    [String] GetContent(
        [String[]]$Lines
    ) {
        if ($this.StartingIndex -eq $this.EndingIndex) {
            return $Lines[$this.StartingIndex].Substring($this.StartingColumn, $this.EndingColumn - $this.StartingColumn);
        }

        [String]$Content = $Lines[$this.StartingIndex].Substring($this.StartingColumn);
        for ($i = $this.StartingIndex + 1; $i -lt $this.EndingIndex; $i++) {
            $Content += $Lines[$i];
        }

        $Content += $Lines[$this.EndingIndex].Substring(0, $this.EndingColumn);
        return $Content;
    }

    [Void] SetContent(
        [String[]]$Lines,
        [String]$Content
    ) {
        if ($this.StartingIndex -eq $this.EndingIndex) {
            $Lines[$this.StartingIndex] = $Lines[$this.StartingIndex].Substring(0, $this.StartingColumn) + $Content + $Lines[$this.StartingIndex].Substring($this.EndingColumn);
            return;
        }

        $Lines[$this.StartingIndex] = $Lines[$this.StartingIndex].Substring(0, $this.StartingColumn) + $Content;
        for ($i = $this.StartingIndex + 1; $i -lt $this.EndingIndex; $i++) {
            $Lines[$i] = '';
        }

        $Lines[$this.EndingIndex] = $Lines[$this.EndingIndex].Substring($this.EndingColumn);
    }
}

class TextSpanUpdater {
    [TextSpan]$TextSpan;
    [ScriptBlock]$CreateNewLines;

    TextRange(
        [Int]$StartingIndex,
        [Int]$EndingIndex,
        [ScriptBlock]$CreateNewLines
    ) {
        $this.StartingIndex = $StartingIndex;
        $this.EndingIndex = $EndingIndex;
        $this.CreateNewLines = $CreateNewLines;
    }
}

class TextEditor {
    [TextDocument]$Document;
    [TextSpanUpdater[]]$RangeEdits;
    [Boolean]$EditApplied;

    TextEditor(
        [TextDocument]$Document
    ) {
        $this.Document = $Document;
        $this.RangeEdits = @();
        $this.EditApplied = $False;
    }

    [Void] AddRangeEdit(
        [Int]$StartingIndex,
        [Int]$EndingIndex,
        [ScriptBlock]$CreateNewLines
    ) {
        if ($this.EditApplied) {
            Invoke-Error 'Cannot add a range edit to a document that has already been applied.';
            return;
        }

        $RangeEdit = [TextSpanUpdater]::new($StartingIndex, $EndingIndex, $CreateNewLines);
        $this.RangeEdits.Add($RangeEdit);
    }

    [Void] ApplyRangeEdits() {
        if ($this.EditApplied) {
            Invoke-Warn 'Cannot apply range edits to a document that has already been applied.';
            return;
        }

        [Int]$CurrentOffset = 0;
        $this.RangeEdits = $this.RangeEdits | Sort-Object -Property StartingIndex;
        foreach ($RangeEdit in $this.RangeEdits) {
            [Int]$StartIndex = $RangeEdit.StartingIndex + $CurrentOffset;
            [Int]$EndIndex = $RangeEdit.EndingIndex + $CurrentOffset;

            [String[]]$LineRange = $this.Document.Lines[$StartIndex..$EndIndex];
            [String[]]$NewLines = $RangeEdit.CreateNewLines.InvokeWithContext($null, [PSVariable]::new('Lines', $LineRange));

            if ($null -eq $NewLines -or $NewLines.Count -eq 0) {
                if ($StartIndex -gt 0) {
                    $this.Document.Lines = $this.Document.Lines[0..($StartIndex - 1)] + $this.Document.Lines[($EndIndex + 1)..($this.Document.Lines.Count - 1)];
                }
                else {
                    $this.Document.Lines = $this.Document.Lines[($EndIndex + 1)..($this.Document.Lines.Count - 1)];
                }
            }
            else {
                if ($StartIndex -gt 0) {
                    $this.Document.Lines = $this.Document.Lines[0..($StartIndex - 1)] + $NewLines + $this.Document.Lines[($EndIndex + 1)..($this.Document.Lines.Count - 1)];
                }
                else {
                    $this.Document.Lines = $NewLines + $this.Document.Lines[($EndIndex + 1)..($this.Document.Lines.Count - 1)];
                }
            }

            $CurrentOffset += $NewLines.Count - $LineRange.Count;
        }

        $this.EditApplied = $True;
    }

    [String] GetContent() {
        if (-not $this.EditApplied) {
            Invoke-Warn 'Cannot get content from a document that has not had it''s edits applied.';
            return $null;
        }

        return $this.Document.Lines -join [Environment]::NewLine;
    }
}

Export-Types -Types (
    [TextDocument],
    [TextSpan],
    [TextSpanUpdater],
    [TextEditor]
);
