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

function Get-Modules {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:Modules; }

    process {
        # Get all the modules in the root/common folder
        # Then also decend into any subfolders and look for a mod.json file.
        # The mod.json file is used to define the exported functions and aliases for modules in the folder.

        [System.Management.Automation.OrderedHashtable]$Local:ModuleDictionary = [Ordered]@{};
        Get-ChildItem -Path $ModuleRoot -Filter 'mod.json' -Recurse | ForEach-Object {
            Invoke-Debug "Found module description file: $($_.FullName)";

            [String]$Local:ModuleDescription = Get-Content -Raw -Path $_.FullName;
            if (-not $Local:ModuleDescription) {
                Invoke-Warn -Message "Module description file is empty: $($_.FullName). Skipping...";
                continue;
            }

            [PSCustomObject]$Local:ModuleDescription = ConvertFrom-Json -InputObject $Local:ModuleDescription;
            if (-not $Local:ModuleDescription) {
                Invoke-Warn -Message "Module description file is not valid JSON: $($_.FullName). Skipping...";
                continue;
            }

            $Local:FullNamePrefix = $_.DirectoryName.Replace($ModuleRoot, '').TrimStart('\');
            $Local:ModuleDescription | ForEach-Object {
                [String]$Local:ModuleName = $_.Name;
                [String]$Local:ModulePath = Join-Path -Path $ModuleRoot -ChildPath $Local:FullNamePrefix -AdditionalChildPath $Local:ModuleName;
                [String]$Local:ExportedFunctions = $_.Functions;
                Invoke-Debug "Found module: $Local:ModuleName, path: $Local:ModulePath, functions: $Local:ExportedFunctions";

                if ($Local:ModuleDictionary[$Local:ModulePath]) {
                    Invoke-Warn -Message "Duplicate module: $Local:ModuleName.";
                    continue;
                }

                $Local:ModuleDictionary.Add($Local:ModuleName, $Local:ModuleDescription);
            }
        };
    }
}

function Get-CompliledContent(
    [Parameter(Mandatory)]
    [String[]]$Lines
) {
    [Tokens[]]$Local:Tokens = $null;
    [ParseError[]]$Local:Errors = $null;
    [Parser]::ParseInput(($Lines | Join-String -Separator "`n"), [ref]$Local:Tokens, [ref]$Local:Errors);

    [Tokens]$Local:Tokens = $Local:Tokens | Where-Object { $_.Kind -ne 'Comment' -and $_.Kind -ne 'NewLine' };

    $Local:Tokens, $Local:Errors;
}

function Get-FilteredContent([Parameter(Mandatory)][String[]]$Content) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:CleanedLines; }

    process {
        $Local:CleanedLines = $Content;

        while ($true) {
            ($Local:StartIndex, $Local:EndIndex) = Find-StartToEndBlock -Lines $Local:CleanedLines -OpenPattern '<#' -ClosePattern '#>';

            if ($Local:StartIndex -ge 0 -and $Local:EndIndex -ge 0) {
                Invoke-Debug -Message "Found comment block at lines $Local:StartIndex to $Local:EndIndex";
                Invoke-Debug -Message "Comment block content: $($Local:CleanedLines[$Local:StartIndex..$Local:EndIndex] | Join-String -Separator "`n")";

                if ($Local:StartIndex -gt 0) {
                    $Local:CleanedLines = $Local:CleanedLines[0..($Local:StartIndex - 1)] + $Local:CleanedLines[($Local:EndIndex + 1)..($Local:CleanedLines.Count - 1)];
                } else {
                    $Local:CleanedLines = $Local:CleanedLines[($Local:EndIndex + 1)..($Local:CleanedLines.Count - 1)];
                }

                continue;
            }

            break;
        }

        # Remove any comments from the content
        $Local:CleanedLines = $Local:CleanedLines | Where-Object { $_ -notmatch '^#' };

        return $Local:CleanedLines;
    }
}

# function Invoke-ParseBody {
#     [CmdletBinding()]
#     param (
#         [Parameter(Mandatory)]
#         [String]$Body
#     )

#     begin { Enter-Scope -Invocation $MyInvocation; }
#     end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:CompiledBody; }

#     process {
#         [System.Management.Automation.Language.Token[]]$Local:Tokens = $null;
#         [System.Management.Automation.Language.ParseError[]]$Local:Errors = $null;
#         [System.Management.Automation.Language.Parser]::ParseInput($Body, [ref]$Local:Tokens, [ref]$Local:Errors);

#         if ($Local:Errors) {
#             $Local:Errors | ForEach-Object {
#                 Write-Host -Object "Error parsing body: $($_.Message)";
#             }

#             Invoke-FailedExit -ExitCode $Script:UNABLE_TO_PARSE_BODY;
#         }

#         [Int16]$Local:Offset = 0;
#         [String]$Local:CompiledBody = $Local:Tokens | ForEach-Object -Parallel {
#             $Local:Kind = $_.Kind;
#             $Local:Text = $_.Text;
#             $Local:Start = $_.Start;
#             $Local:Length = $_.Length;

#             # if ($Local:Kind -eq 'Variable') {
#             #     $Local:VariableName = $Local:Text.Substring(1);
#             #     $Local:VariableValue = Get-Variable -Name $Local:VariableName -ValueOnly -ErrorAction SilentlyContinue;
#             #     if (-not $Local:VariableValue) {
#             #         Invoke-Error -Message "Unable to find variable: $Local:VariableName";
#             #         Invoke-FailedExit -ExitCode $Script:UNABLE_TO_PARSE_BODY;
#             #     }

#             #     $Local:VariableValue = $Local:VariableValue.ToString();
#             #     $Local:Text = $Local:Text.Replace($Local:VariableName, $Local:VariableValue);
#             # }

#             $Local:Text;
#         } | Join-String -Separator '';

#         return $Local:CompiledBody;
#     }
# }

# function Get-UsingStatements(
#     [Parameter(Mandatory)][Token[]]$Tokens,
#     [Parameter(Mandatory)][Int,Int]$Range
# ) {
#     begin { Enter-Scope -Invocation $MyInvocation; }
#     end { Exit-Scope -Invocation $MyInvocation -ReturnValue [ref]$Local:UsingStatements,[ref]$Local:NewRange; }

#     process {
#         [Token[]]$Local:UsingStatements = $Tokens | Where-Object { $_.Kind -eq 'Using' };
#         if ($Local:UsingStatements.Count -eq 0) {
#             return $null,$Range;
#         }




#         return $Local:UsingStatements;
#     }
# }

# function Remove-UsingStatements {
#     param (
#         [System.Management.Automation.Language.Ast]$Ast,
#         [System.Collections.ObjectModel.Collection[System.Management.Automation.Language.Token]]$Tokens
#     )

#     try {
#         # Find 'using' statements in the AST
#         $usingStatements = $Ast.FindAll({ param($ast) $ast -is [System.Management.Automation.Language.UsingStatementAst] }, $true)

#         # Collect the start and end positions of 'using' statements
#         $usingRanges = $usingStatements | ForEach-Object { $_.Extent.StartOffset, $_.Extent.EndOffset }

#         # Filter out tokens that are part of 'using' statements
#         $filteredTokens = $Tokens | Where-Object {
#             $TokenRange = $_.Extent.StartOffset..$_.Extent.EndOffset

#             # Check if the token is outside all 'using' statement ranges
#             $Count = ($usingRanges | Where-Object { ($TokenRange -contains $_) });
#             if ($Count -ne 0) {
#                 Write-Host -Object "Token is part of a using statement: $($_.Extent.Text)"

#                 return $false
#             } else {
#                 return $true
#             }
#         }

#         # Reconstruct the script from filtered tokens
#         $newScript = $filteredTokens | ForEach-Object { $_.Extent.Text } | Out-String -NoNewline

#         return $newScript
#     }
#     catch {
#         Write-Error "Error processing AST: $_"
#     }
# }

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

        [String]$Local:CmdletBinding = $null;
        if ($Local:FilteredLines[0] | Select-String -Quiet -Pattern '(i?)^\s*\[CmdletBinding\(([a-z,\s]+)\)\]') {
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

        # Replace the import environment module with the embeded version
        $Local:ScriptBody = $Local:ScriptBody -replace '(?smi)^Import-Module (\$PSScriptRoot)?([./]*./)common/Environment\.psm1;?\s*$', '';

        [String]$Local:CompiledScript = @"
$Local:RequirmentLines
$Local:CmdletBinding
$Local:ParamBlock
`$Global:CompiledScript = `$true;
`$Global:EmbededModules = [ordered]@{
    $($Local:ModuleTable.GetEnumerator() | Sort-Object Name | ForEach-Object {
        $Local:Key = $_.Key;
        $Local:Value = $_.Value;
    "`"$Local:Key`" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
        $(Get-FilteredContent -Content $Local:Value | Join-String -Separator "`n`t`t")
    };"
    } | Join-String -Separator "```n`t")
}
$Local:ScriptBody
$(if ($Local:InvokeMain) {
    "(New-Module -ScriptBlock `$Global:EmbededModules['Environment.psm1'] -AsCustomObject -ArgumentList `$MyInvocation.BoundParameters).'Invoke-RunMain'(`$MyInvocation, $Local:InvokeMain);"
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


