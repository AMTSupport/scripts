#Requires -Version 7.3

[CmdletBinding(SupportsShouldProcess)]
Param(
    [Parameter(Mandatory, HelpMessage="The path of the target script to compile a merged version of.")]
    [ValidateScript({ Test-Path $_ -IsValid }, ErrorMessage = "Target script file does not exist: {0}")]
    [ValidateScript({ $_.EndsWith('.ps1') }, ErrorMessage = "Target script file must be a PowerShell script file: {0}")]
    [String[]]$CompileScripts,

    [Parameter(HelpMessage="The folders or files to search for modules to merge into the target script.")]
    [ValidateScript({ Test-Path $_ -IsValid }, ErrorMessage = "Module folder does not exist: {0}")]
    [ValidateScript({ Test-Path $_ -PathType 'Container' }, ErrorMessage = "Module folder is not a folder: {0}")]
    [String[]]$Modules = @($PSScriptRoot + '\common'),

    [Parameter(HelpMessage="The folder to write the merged version of the target script to, if not specified the merged version will be written to the console.")]
    [ValidateScript({ Test-Path $_ -IsValid }, ErrorMessage = "Output file path is invalid: {0}")]
    [ValidateScript({ Test-Path $_ -PathType 'Container' }, ErrorMessage = "Output file path is not a folder: {0}")]
    [String]$Output
)

function Find-StartToEndBlock(
    [Parameter(Mandatory)][String[]]$Lines,
    [Parameter(Mandatory)][String]$OpenPattern,
    [Parameter(Mandatory)][String]$ClosePattern
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:StartIndex,$Local:EndIndex; }

    process {
        [Int32]$Local:StartIndex = -1;
        [Int32]$Local:EndIndex = -1;
        [Int32]$Local:OpenLevel = 0;
        for ($Local:Index = 0; $Local:Index -lt $Lines.Count; $Local:Index++) {
            $Local:Line = $Lines[$Local:Index];

            if ($Local:Line -match $OpenPattern) {
                if ($Local:OpenLevel -eq 0) {
                    $Local:StartIndex = $Local:Index;
                }

                $Local:OpenLevel += ($Local:Line | Select-String -Pattern $OpenPattern -AllMatches).Matches.Count;
            }

            if ($Local:Line -match $ClosePattern) {
                $Local:OpenLevel -= ($Local:Line | Select-String -Pattern $ClosePattern -AllMatches).Matches.Count;

                if ($Local:OpenLevel -eq 0) {
                    $Local:EndIndex = $Local:Index;
                    break;
                }
            }
        }

        return $Local:StartIndex,$Local:EndIndex;
    }
}

function Get-ModuleDefinitions {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:ModuleTable; }

    process {
        [HashTable]$Local:ModuleTable = @{};
        foreach ($Local:Module in Get-ChildItem -Path $Modules -Filter '*.psm1') {
            if ($Local:ModuleTable[$Local:Module.Name]) {
                Write-Warning -Message "Duplicate module name found: $($Local:Module.Name). Skipping...";
                continue;
            }

            Write-Debug -Message "Adding module: $($Local:Module.Name)";
            $Local:Lines = (Get-Content -Raw -Path $Local:Module.FullName) -split "`n" | Where-Object { $_.Trim() };
            if (-not $Local:Lines -or $Local:Lines.Count -eq 0) {
                Write-Debug -Message "Module content is empty. Skipping...";
                continue;
            }

            $Local:ModuleTable.Add($Local:Module.Name, $Local:Lines);
        }

        return $Local:ModuleTable;
    }
}

function Get-Requirements([Parameter(Mandatory)][String[]]$Lines, [HashTable]$RequirementsTable) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:RequirmentsTable; }

    process {
        [HashTable]$Local:Requirements = @{};
        $RequirementsTable.GetEnumerator() | ForEach-Object {
            $Local:Key = $_.Key;
            switch ($_.Value) {
                { $_ -is [Object[]] } { $Local:Requirements.Add($Local:Key, $_); }
                Default { $Local:Requirements.Add($Local:Key, @($_)); }
            }
        };


        $Lines | Select-String -Pattern '^\s*#Requires -(?<type>[A-Z]+) (?<value>.+)$' | ForEach-Object {
            $Local:Match = $_.Matches[0];
            $Local:Type = $Local:Match.Groups['type'].Value;
            $Local:Value = $Local:Match.Groups['value'].Value;

            if ($Local:Type -eq 'Modules') {
                $Local:Value = $Local:Value.Split(',') | ForEach-Object { $_.Trim() };
            } else {
                $Local:Value = $Local:Value.Trim();
            }

            if ($Local:RequirementsTable[$Local:Type]) {
                $Local:Requirements[$Local:Type] += $Local:Value;
            } else {
                $Local:Requirements.Add($Local:Type, @($Local:Value));
            }
        }

        [HashTable]$Local:RequirmentsTable = @{};
        foreach ($Local:Requirement in $Local:Requirements.GetEnumerator()) {
            $Local:UniqueValues = $Local:Requirement.Value | Sort-Object -Unique;
            $Local:SelectedValue = switch ($Local:Requirement.Key) {
                'Version' { $Local:UniqueValues | ForEach-Object { [Version]$_ } | Sort-Object -Descending | Select-Object -First 1; }
                Default { $Local:UniqueValues; }
            }

            $Local:RequirmentsTable.Add($Local:Requirement.Key, $Local:SelectedValue);
        }

        return $Local:RequirmentsTable;
    }
}

function Get-FilteredContent([Parameter(Mandatory)][String[]]$Content) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:CleanedLines; }

    process {
        $Local:CleanedLines = $Content;

        while ($true) {
            ($Local:StartIndex, $Local:EndIndex) = Find-StartToEndBlock -Lines $Local:CleanedLines -OpenPattern '<#' -ClosePattern '#>';

            if ($Local:StartIndex -ge 0 -and $Local:EndIndex -ge 0) {
                $Local:CleanedLines = $Local:CleanedLines[0..($Local:StartIndex - 1)] + $Local:CleanedLines[($Local:EndIndex + 1)..($Local:CleanedLines.Count - 1)];
                continue;
            }

            break;
        }

        # Remove any comments from the content
        $Local:CleanedLines = $Local:CleanedLines | Where-Object { $_ -notmatch '^#' };

        return $Local:CleanedLines;
    }
}

function New-CompiledScript(
    [Parameter(Mandatory)][ValidateNotNull()][String[]]$Lines,
    [Parameter(Mandatory)][ValidateNotNull()][HashTable]$ModuleTable,
    [Parameter(Mandatory)][ValidateNotNull()][HashTable]$Requirements
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:CompiledScript; }

    process {
        [String[]]$Local:FilteredLines = Get-FilteredContent -Content $Lines;

        [String]$Local:RequirmentLines = $Requirements.GetEnumerator() | ForEach-Object {
            $Local:Type = $_.Key;
            $Local:Value = $_.Value;

            "#Requires -${Type} ${Value}"
        } | Join-String -Separator "`n";

        [String]$Local:ParamBlock = $null;
        if ($Local:FilteredLines[0] | Select-String -Quiet -Pattern '(i?)^\s*param\s*\(') {
            ($Local:ParamStart, $Local:ParamEnd) = Find-StartToEndBlock -Lines $Local:FilteredLines -OpenPattern '\(' -ClosePattern '\)';

            [String]$Local:ParamBlock = $Local:FilteredLines[$Local:ParamStart..$Local:ParamEnd] | Join-String -Separator "`n";
            [String[]]$Local:FilteredLines = $Local:FilteredLines[($Local:ParamEnd + 1)..($Local:FilteredLines.Count - 1)];
        }

        [String]$Local:InvokeMain = $null;
        [Int32]$Local:MatchIndex = -1;
        $Local:FilteredLines | ForEach-Object {
            if ($_ | Select-String -Pattern '(?smi)^Invoke-RunMain\s*(?:-Invocation(?:\s*|=)?)?(?<invocation>\$[A-Z]+)\s*(?:-Main(?:\s*|=)?)?{') {
                $Local:MatchIndex = $Local:FilteredLines.IndexOf($_);
                return;
            }
        }
        if ($Local:MatchIndex -ne -1) {
            Write-Host -ForegroundColor Cyan -Object "Found Invoke-RunMain line: $Local:MatchIndex";

            ($Local:ScriptStart, $Local:ScriptEnd) = Find-StartToEndBlock -Lines $Local:FilteredLines[($Local:MatchIndex)..($Local:FilteredLines.Count)] -OpenPattern '\{' -ClosePattern '\}';
            $Local:ScriptStart += $Local:MatchIndex;
            $Local:ScriptEnd += $Local:MatchIndex;
            $Local:InvokeMain = $Local:FilteredLines[$Local:ScriptStart..$Local:ScriptEnd] | Join-String -Separator "`n";

            Write-Host -ForegroundColor Cyan -Object "Found Invoke-RunMain block at lines $Local:ScriptStart to $Local:ScriptEnd";
            Write-Host -ForegroundColor Cyan -Object "Invoke-RunMain block content: $Local:InvokeMain";

            if ($Local:ScriptStart -gt 0) {
                $Local:BeforeMain = $Local:FilteredLines[0..($Local:ScriptStart - 1)];
                $Local:FilteredLines = $Local:FilteredLines[($Local:ScriptEnd + 1)..($Local:FilteredLines.Count)] + $Local:BeforeMain;
            } else {
                $Local:FilteredLines = $Local:FilteredLines[($Local:ScriptEnd + 1)..($Local:FilteredLines.Count)];
            }

            $Local:InvokeMain = $Local:InvokeMain -replace '(?smi)^Invoke-RunMain\s*(?:-Invocation(?:\s*|=)?)?(?<invocation>\$[A-Z]+)\s*(?:-Main(?:\s*|=)?)?', '';
            # Remove the semi-colon from the end of the Invoke-RunMain block
            $Local:InvokeMain = $Local:InvokeMain -replace ';?\s*$', '';
        }

        [String]$Local:ScriptBody = $Local:FilteredLines | Join-String -Separator "`n";

        # Replace the import environment module with the embeded version
        $Local:ScriptBody = $Local:ScriptBody -replace '(?smi)^Import-Module (\$PSScriptRoot)?([./]*./)common/Environment\.psm1;?\s*$', '';

        [String]$Local:CompiledScript = @"
$Local:RequirmentLines
$Local:ParamBlock
`$Global:CompiledScript = `$true;
`$Global:EmbededModules = @{
    $($Local:ModuleTable.GetEnumerator() | ForEach-Object {
        $Local:Key = $_.Key;
        $Local:Value = $_.Value;
    "`"$Local:Key`" = {
        $(Get-FilteredContent -Content $Local:Value | Join-String -Separator "`n`t`t")
    };"
    } | Join-String -Separator "```n`t")
}
$Local:ScriptBody
$(if ($Local:InvokeMain) {
    "(New-Module -ScriptBlock `$Global:EmbededModules['Environment.psm1'] -AsCustomObject).'Invoke-RunMain'(`$MyInvocation, $Local:InvokeMain);"
})
"@;

        return $Local:CompiledScript;
    }
}

Import-Module ./common/Environment.psm1;

Invoke-RunMain $MyInvocation {
    [HashTable]$Local:ModuleTable = Get-ModuleDefinitions;
    [HashTable]$Local:ModuleRequirements = @{};
    $Local:ModuleTable.GetEnumerator() | ForEach-Object {
        $Local:ModuleRequirements = Get-Requirements -Lines $_.Value -Requirements $Local:ModuleRequirements;
    };

    foreach ($Local:Script in $CompileScripts) {
        [System.IO.FileInfo]$Local:ScriptFile = Get-Item -Path $Local:Script;
        [String[]]$Local:Lines = (Get-Content -Raw -Path $Local:ScriptFile).Split("`n") | Where-Object { $_.Trim() };
        [HashTable]$Local:Requirements = Get-Requirements -Lines $Local:Lines -Requirements $Local:ModuleRequirements;
        [String]$Local:CompiledScript = New-CompiledScript -Lines $Local:Lines -ModuleTable $Local:ModuleTable -Requirements $Local:Requirements;

        if (-not $Output) {
            Write-Host -ForegroundColor Cyan -Object $Local:CompiledScript;
        } else {
            [System.IO.FileInfo]$Local:OutputFile = Join-Path -Path $Output -ChildPath $Local:ScriptFile.Name;
            if (Test-Path $Local:OutputFile) {
                if (Get-UserConfirmation -Title "Output file [$($Local:OutputFile | Split-Path -LeafBase)] already exists" -Question 'Do you want to overwrite it?' -DefaultChoice $true) {
                    Write-Host -ForegroundColor Cyan -Object 'Output file already exists. Deleting...';
                    Remove-Item -Path $Local:OutputFile -Force | Out-Null;
                } else {
                    Write-Host -ForegroundColor Red "Output file already exists: $($Local:OutputFile)";
                    continue
                }
            }

            New-Item -Path $Local:OutputFile -ItemType File -Force | Out-Null;
            Out-File -FilePath $Local:OutputFile -Encoding UTF8 -InputObject $Local:CompiledScript;
        }
    }
};


