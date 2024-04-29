Using module './Text.psm1';

Using namespace System.Management.Automation.Language;

class Module: TextEditor {
    [String]$Name;
    [HashTable]$Requirements;
    hidden [String[]]$Lines;
    hidden [TextEditor[]]$TextRanges = @();
    hidden [ScriptBlockAst]$Ast;

    Module(
        [String]$Name,
        [String[]]$Lines
    ) {

        $this.Name = $Name;
        $this.Lines = $Lines;
        $this.EditApplied = $False;
        $this.Ast = [Parser]::ParseInput($Lines -join "`n", [ref]$null, [ref]$null);

        $this.Requirements = @{
            Version = $null;
            Modules = Get-DeclaredModules -Ast $this.Ast;
        };

        # $Lines | Select-String -Pattern '^\s*#Requires -(?<type>[A-Z]+) (?<value>.+)$' | ForEach-Object {
        #     $Local:Match = $_.Matches[0];
        #     $Local:Type = $Local:Match.Groups['type'].Value;
        #     $Local:Value = $Local:Match.Groups['value'].Value;

        #     if ($Local:Type -eq 'Modules') {
        #         $Local:Value = $Local:Value.Split(',') | ForEach-Object { $_.Trim() };
        #     }
        #     else {
        #         $Local:Value = $Local:Value.Trim();
        #     }

        #     if ($Local:RequirementsTable[$Local:Type]) {
        #         $Local:Requirements[$Local:Type] += $Local:Value;
        #     }
        #     else {
        #         $Local:Requirements.Add($Local:Type, @($Local:Value));
        #     }
        # }

        # [HashTable]$Local:RequirmentsTable = @{};
        # foreach ($Local:Requirement in $Local:Requirements.GetEnumerator()) {
        #     $Local:UniqueValues = $Local:Requirement.Value | Sort-Object -Unique;
        #     $Local:SelectedValue = switch ($Local:Requirement.Key) {
        #         'Version' { $Local:UniqueValues | ForEach-Object { [Version]$_ } | Sort-Object -Descending | Select-Object -First 1; }
        #         Default { $Local:UniqueValues; }
        #     }

        #     $Local:RequirmentsTable.Add($Local:Requirement.Key, $Local:SelectedValue);
        # }
    }

    [Void] AddRegexEdit(
        [String]$StartingPattern,
        [String]$EndingPattern,
        [ScriptBlock]$CreateNewLines
    ) {
        if ($this.EditApplied) {
            Invoke-Error 'Cannot add a regex edit to a module that has already been applied.';
            return;
        }

        while ($True) {
            ($Local:StartIndex, $Local:EndIndex) = Find-StartToEndBlock -Lines $this.Lines -OpenPattern $StartingPattern -ClosePattern $EndingPattern;
            if ($Local:StartIndex -eq -1 -or $Local:EndIndex -eq -1) {
                break;
            }

            $Private:TextSpan = [TextSpan]::new($Local:StartIndex, $Local:EndIndex);
            $Local:RangeEdit = [RangeEdit]::new($Local:StartIndex, $Local:EndIndex, $CreateNewLines);
            $this.RangeEdits.Add($Local:RangeEdit);
        }
    }

    [Void] AddRangeEdit(
        [Int]$StartingIndex,
        [Int]$EndingIndex,
        [ScriptBlock]$CreateNewLines
    ) {
        if ($this.EditApplied) {
            Invoke-Error 'Cannot add a range edit to a module that has already been applied.';
            return;
        }

        $Local:RangeEdit = [RangeEdit]::new($StartingIndex, $EndingIndex, $CreateNewLines);
        $this.RangeEdits.Add($Local:RangeEdit);
    }

    [Void] ApplyRangeEdits() {
        if ($this.EditApplied) {
            Invoke-Warn 'Cannot apply range edits to a module that has already been applied.';
            return;
        }

        [Int]$Local:CurrentOffset = 0;
        $this.RangeEdits = $this.RangeEdits | Sort-Object -Property StartingIndex;
        foreach ($Local:RangeEdit in $this.RangeEdits) {
            [Int]$Private:StartIndex = $Local:RangeEdit.StartingIndex + $Local:CurrentOffset;
            [Int]$Private:EndIndex = $Local:RangeEdit.EndingIndex + $Local:CurrentOffset;

            [String[]]$Local:LineRange = $this.Lines[$Private:StartIndex..$Private:EndIndex];
            [String[]]$Local:NewLines = $Local:RangeEdit.CreateNewLines.InvokeWithContext($null, [PSVariable]::new('Lines', $Local:LineRange));

            if ($null -eq $NewLines -or $NewLines.Count -eq 0) {
                if ($Private:StartIndex -gt 0) {
                    $this.Lines = $this.Lines[0..($Private:StartIndex - 1)] + $this.Lines[($Private:EndIndex + 1)..($this.Lines.Count - 1)];
                }
                else {
                    $this.Lines = $this.Lines[($Private:EndIndex + 1)..($this.Lines.Count - 1)];
                }
            }
            else {
                if ($Private:StartIndex -gt 0) {
                    $this.Lines = $this.Lines[0..($Private:StartIndex - 1)] + $Local:NewLines + $this.Lines[($Private:EndIndex + 1)..($this.Lines.Count - 1)];
                }
                else {
                    $this.Lines = $Local:NewLines + $this.Lines[($Private:EndIndex + 1)..($this.Lines.Count - 1)];
                }
            }

            $Local:CurrentOffset += $Local:NewLines.Count - $Local:LineRange.Count;
        }

        $this.EditApplied = $True;
    }
}
