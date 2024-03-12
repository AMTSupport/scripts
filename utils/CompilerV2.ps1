<#
.SYNOPSIS
    Compiles a PowerShell script file and merges all the modules it uses into the script.

.DESCRIPTION
    This script can take any number of local PowerShell module files, merge and compile them into a single script file.

    All #Requires statements are merged into the final script file.
    All Using statements are merged into the final script file.

    The modules are merged into the final script in a dependency order, detecting used functions and classes,
    this means the script will error if there are any circular dependencies, this is a limitation of the current implementation.

    The final script is compiled into a single file, this means that the script can be run on any machine without the need to install the modules.

.EXAMPLE
    .\CompilerV2.ps1 -InputFile .\src\automation\Invoke-RebootNotice.ps1 -OutputFile .\Invoke-RebootNotice.ps1
    This will compile the Invoke-RebootNotice.ps1 script and output the result to Invoke-RebootNotice.ps1
#>


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
