<#
. SYNOPSIS
    Compiles a PowerShell script file and merges all the modules it uses into the script.

. DESCRIPTION
    This script can take any number of local PowerShell module files, merge and compile them into a single script file.

    All #Requires statements are merged into the final script file.
    Currently this only supports the current #Requires statement types: 'Version'

    The modules that are merged into the final script are ordered by the module name,
    using numbers to prefix the module is the current solution to import the modules in the correct order.
.NOTES
    TODO: Add support for secret insertion into the compiled script using a .secrets file, or maybe sops.
          This would work by adding these secrets only into the parameters of the main function.
    TODO: Scan the script for all functions being used, only merge the modules that are required for the script to run.
          Alternatively, we could also do a semi-merge where remove the unused functions from modules before merging them.
    TODO: Use AST to parse the script instead of the current method of regex and string manipulation.
          This would allow us to do a more accurate merge and also remove the need for the current method of removing comments.
    TODO: Instead of ordering scripts by their names, we could scan the script for its used functions and then order the modules by the functions they export.
          This would allow us to remove the need for the current method of ordering the modules by their names.
    TODO: Add support for using statements in the script, im not sure how to handle this yet.
    TODO: While compiling the script check it with PSScriptAnalyzer to make sure it is valid.
          In the same vain we could also check for any functions or variables that could be undefined and cause errors.
    TODO: Embed non local modules too, this would allow us to compile scripts that use modules from the PowerShell Gallery.
          This would require us to download the module and extract the files to merge them into the script.
    TODO: Use the Using modules statement to define the modules that are being used in the script.
          This would allow us to remove the need for the current method of ordering the modules by their names.
#>

#Requires -Version 7.1
Using namespace System.Management.Automation.Language;

[CmdletBinding(SupportsShouldProcess)]
Param(
    [Parameter(Mandatory, HelpMessage="The path of the target script to compile a merged version of.")]
    [ValidateScript({ Test-Path $_ -IsValid }, ErrorMessage = "Target script file does not exist: {0}")]
    [ValidateScript({ $_.EndsWith('.ps1') }, ErrorMessage = "Target script file must be a PowerShell script file: {0}")]
    [String[]]$CompileScripts,

    [Parameter(HelpMessage="The folders or files to search for modules to merge into the target script.")]
    [ValidateScript({ Test-Path $_ -IsValid }, ErrorMessage = "Module folder does not exist: {0}")]
    [ValidateScript({ Test-Path $_ -PathType 'Container' }, ErrorMessage = "Module folder is not a folder: {0}")]
    [String[]]$Modules = @("$PSScriptRoot\..\src\common"),

    [Parameter(HelpMessage="The root folder to search for modules to merge into the target script.")]
    [ValidateScript({ Test-Path $_ -IsValid }, ErrorMessage = "Module root folder does not exist: {0}")]
    [ValidateScript({ Test-Path $_ -PathType 'Container' }, ErrorMessage = "Module root folder is not a folder: {0}")]
    [String]$ModuleRoot = "$PSScriptRoot\..\src",

    [Parameter(HelpMessage="The folder to write the merged version of the target script to, if not specified the merged version will be written to the console.")]
    [ValidateScript({ Test-Path $_ -IsValid }, ErrorMessage = "Output file path is invalid: {0}")]
    [ValidateScript({ Test-Path $_ -PathType 'Container' }, ErrorMessage = "Output file path is not a folder: {0}")]
    [String]$Output,

    [Parameter(HelpMessage="If specified, the output file will be overwritten if it already exists.")]
    [Switch]$Force,

    [Parameter(DontShow, HelpMessage="If this was ran from within another script.")]
    [Switch]$InnerInvocation
)

function Find-StartToEndBlock(
    [Parameter(Mandatory)][String[]]$Lines,
    [Parameter(Mandatory)][String]$OpenPattern,
    [Parameter(Mandatory)][String]$ClosePattern
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:StartIndex,$Local:EndIndex; }

    process {
        if (-not $Lines -or $Lines.Count -eq 0) {
            return -1,-1;
        }

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

function Invoke-FixLines(
    [Parameter(Mandatory)][ValidateNotNull()][String[]]$Lines
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:FixedLines; }

    process {
        function Remove-Index(
            [Parameter(Mandatory)][String[]]$Lines,
            [Parameter(Mandatory)][Int32]$StartIndex,
            [Parameter(Mandatory)][Int32]$EndIndex
        ) {
            if ($StartIndex -gt 0) {
                $Lines = $Lines[0..($StartIndex - 1)] + $Lines[($EndIndex + 1)..($Lines.Count - 1)];
            } else {
                $Lines = $Lines[($EndIndex + 1)..($Lines.Count - 1)];
            }

            return $Lines;
        }

        function Update-Range(
            [Parameter(Mandatory)][String[]]$Lines,
            [Parameter(Mandatory)][Int32]$StartIndex,
            [Parameter(Mandatory)][Int32]$EndIndex,
            [Parameter(Mandatory)][String[]]$UpdatedLines
        ) {
            if ($StartIndex -gt 0) {
                $Lines = $Lines[0..($StartIndex - 1)] + $UpdatedLines + $Lines[($EndIndex + 1)..($Lines.Count - 1)];
            } else {
                $Lines = $UpdatedLines + $Lines[($EndIndex + 1)..($Lines.Count - 1)];
            }

            return $Lines;
        }

        function Invoke-DebugIndex(
            [Parameter(Mandatory)][String]$Type,
            [Parameter(Mandatory)][String[]]$Lines,
            [Parameter(Mandatory)][Int32]$StartIndex,
            [Parameter(Mandatory)][Int32]$EndIndex
        ) {
            Invoke-Debug -Message @"
Found ${Type} at lines $StartIndex..$EndIndex
$($Lines[$StartIndex..$EndIndex] | Join-String -Separator "`n")
"@;
        }

        [String[]]$Local:FixedLines = $Lines;

        # Look for any mulitline strings, capture them and trim the whitespace from the start to ensure they are correctly merged.
        while ($True) {
            ($Local:StartIndex, $Local:EndIndex) = Find-StartToEndBlock -Lines $Local:FixedLines -OpenPattern '^\s*.*@"' -ClosePattern '^\s+.*"@';
            if ($Local:StartIndex -eq -1 -or $Local:EndIndex -eq -1) {
                Invoke-Debug 'No more multiline strings found';
                break
            }

            Invoke-DebugIndex -Type 'multiline string' -Lines $Local:FixedLines -StartIndex $Local:StartIndex -EndIndex $Local:EndIndex;

            # If the multiline is not at the start of the content it does not need to be trimmed, so we skip it.
            if (-not $Local:FixedLines[$Local:StartIndex].StartsWith('@"')) {
                $Local:StartIndex++;
            }

            # Get the multiline indent level from the last line of the string.
            # This is used so we don't remove any whitespace that is part of the actual string formatting.
            $Local:IndentLevel = $Local:FixedLines[$Local:EndIndex].IndexOf('"@');

            # Trim the leading whitespace from the multiline string.
            [String[]]$Local:UpdatedLines = $Local:FixedLines[$Local:StartIndex..$Local:EndIndex] | ForEach-Object { $_.Substring($Local:IndentLevel) };

            Invoke-Debug "Updated multiline string: `n$($Local:UpdatedLines | Join-String -Separator "`n")";
            $Local:FixedLines = Update-Range -Lines $Local:FixedLines -StartIndex $Local:StartIndex -EndIndex $Local:EndIndex -UpdatedLines $Local:UpdatedLines;
        };

        # Remove any Document Blocks from the content
        while ($True) {
            ($Local:StartIndex, $Local:EndIndex) = Find-StartToEndBlock -Lines $Local:FixedLines -OpenPattern '<#' -ClosePattern '#>';

            if ($Local:StartIndex -eq -1 -or $Local:EndIndex -eq -1) {
                Invoke-Debug 'No more comment blocks found';
                break
            }

            Invoke-DebugIndex -Type 'comment block' -Lines $Local:FixedLines -StartIndex $Local:StartIndex -EndIndex $Local:EndIndex;

            $Local:FixedLines = Remove-Index -Lines $Local:FixedLines -StartIndex $Local:StartIndex -EndIndex $Local:EndIndex;
        }

        # Must be done after the comment blocks are removed, as it would remove the closing comment block.
        # Remove any empty lines and comments from the content
        # TODO :: Remove comments from the end of statements too? eg. $Var = 'Value' # This is a comment
        $Local:FixedLines = $Local:FixedLines | Where-Object { $_ -ne '' -and $_ -notmatch '^\s*#' };

        Invoke-Debug 'Finished fixing lines';
        Invoke-Debug "Fixed lines: `n$($Local:FixedLines | Join-String -Separator "`n")";
        return $Local:FixedLines;
    }
}

function New-CompiledScript(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][String[]]$Lines,
    [Parameter(Mandatory)][ValidateNotNull()][HashTable]$ModuleTable,
    [Parameter(Mandatory)][ValidateNotNull()][HashTable]$Requirements
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:CompiledScript; }

    process {
        [String[]]$Local:FilteredLines = Invoke-FixLines -Lines $Lines;

        [String]$Local:RequirmentLines = $Requirements.GetEnumerator() | ForEach-Object {
            $Local:Type = $_.Key;
            $Local:Value = $_.Value;

            "#Requires -${Type} ${Value}"
        } | Join-String -Separator "`n";

        [String]$Local:CmdletBinding = $null;
        if ($Local:FilteredLines[0] | Select-String -Quiet -Pattern '(i?)^\s*\[CmdletBinding\(([a-z,\s]*)\)\]') {
            Invoke-Debug -Message 'Found CmdletBinding attribute';

            ($Local:ParamStart, $Local:ParamEnd) = Find-StartToEndBlock -Lines $Local:FilteredLines -OpenPattern '\[' -ClosePattern '\]';
            Invoke-Debug -Message "Found CmdletBinding attribute at lines $Local:ParamStart to $Local:ParamEnd";
            Invoke-Debug -Message "CmdletBinding attribute content: $($Local:FilteredLines[$Local:ParamStart..$Local:ParamEnd] | Join-String -Separator "`n")";

            [String]$Local:CmdletBinding = $Local:FilteredLines[$Local:ParamStart..$Local:ParamEnd] | Join-String -Separator "`n";
            [String[]]$Local:FilteredLines = $Local:FilteredLines[($Local:ParamEnd + 1)..($Local:FilteredLines.Count - 1)];
        }

        [String]$Local:ParamBlock = $null;
        if ($Local:FilteredLines[0] | Select-String -Quiet -Pattern '(i?)^\s*param\s*\(') {
            Invoke-Debug -Message 'Found param block';

            ($Local:ParamStart, $Local:ParamEnd) = Find-StartToEndBlock -Lines $Local:FilteredLines -OpenPattern '\(' -ClosePattern '\)';
            Invoke-Debug -Message "Found param block at lines $Local:ParamStart to $Local:ParamEnd";
            Invoke-Debug -Message "Param block content: $($Local:FilteredLines[$Local:ParamStart..$Local:ParamEnd] | Join-String -Separator "`n")";

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
            Invoke-Debug "Found Invoke-RunMain line: $Local:MatchIndex";

            ($Local:ScriptStart, $Local:ScriptEnd) = Find-StartToEndBlock -Lines $Local:FilteredLines[($Local:MatchIndex)..($Local:FilteredLines.Count)] -OpenPattern '\{' -ClosePattern '\}';
            $Local:ScriptStart += $Local:MatchIndex;
            $Local:ScriptEnd += $Local:MatchIndex;
            $Local:InvokeMain = $Local:FilteredLines[$Local:ScriptStart..$Local:ScriptEnd] | Join-String -Separator "`n";

            Invoke-Debug "Found Invoke-RunMain block at lines $Local:ScriptStart to $Local:ScriptEnd";
            Invoke-Debug "Invoke-RunMain block content: $Local:InvokeMain";

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

        # Replace the import environment with an empty string.
        $Local:ScriptBody = $Local:ScriptBody -replace '(?smi)^Import-Module\s(?:\$PSScriptRoot)?(?:[/\\\.]*(?:(?:src|common)[/\\])+)00-Environment\.psm1;?\s*$', '';

        [String]$Local:CompiledScript = @"
$Local:RequirmentLines
$Local:CmdletBinding
$Local:ParamBlock
`$Global:CompiledScript = `$true;
`$Global:EmbededModules = [ordered]@{
    $($Local:ModuleTable.GetEnumerator() | Sort-Object Name | ForEach-Object {
        $Local:Key = $_.Key | Split-Path -LeafBase;
        $Local:Value = $_.Value;
    "`"$Local:Key`" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
$(
    # We indent lines before running the fix lines function so multiline strings are correctly indented.
    [String[]]$Local:IndentedLines = $Local:Value | ForEach-Object { "`t`t$_" };
    Invoke-FixLines $Local:IndentedLines | Join-String -Separator "`n";
)
    };"
    } | Join-String -Separator "```n`t")
}
$Local:ScriptBody
$(if ($Local:InvokeMain) {
    "(New-Module -ScriptBlock `$Global:EmbededModules['00-Environment'] -AsCustomObject -ArgumentList `$MyInvocation.BoundParameters).'Invoke-RunMain'(`$MyInvocation, $Local:InvokeMain);"
})
"@;

        return $Local:CompiledScript;
    }
}

if (-not $InnerInvocation) {
    Import-Module $PSScriptRoot/../src/common/00-Environment.psm1 -ErrorAction Stop;
}

Invoke-RunMain $MyInvocation -DontImport:$InnerInvocation -HideDisclaimer:$InnerInvocation {
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
            Invoke-Info $Local:CompiledScript;
        } else {
            [System.IO.FileInfo]$Local:OutputFile = Join-Path -Path $Output -ChildPath $Local:ScriptFile.Name;
            if (Test-Path $Local:OutputFile) {
                if ($Force -or (Get-UserConfirmation -Title "Output file [$($Local:OutputFile | Split-Path -LeafBase)] already exists" -Question 'Do you want to overwrite it?' -DefaultChoice $true)) {
                    Invoke-Info 'Output file already exists. Deleting...';
                    Remove-Item -Path $Local:OutputFile -Force | Out-Null;
                } else {
                    Invoke-Error "Output file already exists: $($Local:OutputFile)";
                    continue
                }
            }

            New-Item -Path $Local:OutputFile -ItemType File -Force | Out-Null;
            Out-File -FilePath $Local:OutputFile -Encoding UTF8 -InputObject $Local:CompiledScript;
        }
    }
};


