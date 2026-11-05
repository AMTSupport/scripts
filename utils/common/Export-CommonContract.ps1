function ConvertTo-ContractString {
    Param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast
    )

    if ($Ast -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Ast.Value
    }

    if ($Ast -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
        return $Ast.Value
    }

    $Text = $Ast.Extent.Text.Trim()
    if ($Text.Length -ge 2) {
        $StartsAndEndsSingleQuoted = $Text.StartsWith("'") -and $Text.EndsWith("'")
        $StartsAndEndsDoubleQuoted = $Text.StartsWith('"') -and $Text.EndsWith('"')
        if ($StartsAndEndsSingleQuoted -or $StartsAndEndsDoubleQuoted) {
            return $Text.Substring(1, $Text.Length - 2)
        }
    }

    return $Text
}

function Get-ContractExportNames {
    Param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast
    )

    if ($Ast -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        $Names = foreach ($Element in $Ast.Elements) {
            Get-ContractExportNames -Ast $Element
        }

        return @($Names)
    }

    if ($Ast -is [System.Management.Automation.Language.ArrayExpressionAst]) {
        $Names = foreach ($Statement in $Ast.SubExpression.Statements) {
            Get-ContractExportNames -Ast $Statement
        }

        return @($Names)
    }

    $RawNames = (ConvertTo-ContractString -Ast $Ast) -split ','
    $Names = foreach ($RawName in $RawNames) {
        $Name = $RawName.Trim()
        if (-not [String]::IsNullOrWhiteSpace($Name)) {
            $Name
        }
    }

    return @($Names)
}

function Get-ContractUsingReference {
    Param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.UsingStatementAst]$UsingStatement
    )

    if ($null -ne $UsingStatement.Name) {
        return $UsingStatement.Name.Value
    }

    if ($UsingStatement.ModuleSpecification -is [System.Management.Automation.Language.HashtableAst]) {
        $PairData = foreach ($Pair in $UsingStatement.ModuleSpecification.KeyValuePairs) {
            [PSCustomObject]@{
                Key   = ConvertTo-ContractString -Ast $Pair.Item1
                Value = ConvertTo-ContractString -Ast $Pair.Item2
            }
        }

        $PairText = ($PairData | Sort-Object -Property Key | ForEach-Object {
            "{0}={1}" -f $_.Key, $_.Value
        }) -join ';'

        return "@{$PairText}"
    }

    return ($UsingStatement.Extent.Text -replace '\s+', ' ').Trim()
}

function Get-CommonModuleSurface {
    [CmdletBinding()]
    [OutputType([hashtable])]
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$CommonRoot
    )

    $ResolvedCommonRoot = (Resolve-Path -Path $CommonRoot -ErrorAction Stop).Path
    $ModuleFiles = Get-ChildItem -Path $ResolvedCommonRoot -Filter '*.psm1' -File | Sort-Object -Property Name

    $ExportsByModule = [ordered]@{}
    $UsingByModule = [ordered]@{}

    foreach ($ModuleFile in $ModuleFiles) {
        $Tokens = $null
        $ParseErrors = $null
        $ModuleAst = [System.Management.Automation.Language.Parser]::ParseFile(
            $ModuleFile.FullName,
            [ref]$Tokens,
            [ref]$ParseErrors
        )

        $BlockingParseErrors = @(
            $ParseErrors | Where-Object { $_.ErrorId -ne 'ModuleNotFoundDuringParse' }
        )

        if ($BlockingParseErrors.Count -gt 0) {
            $Messages = ($BlockingParseErrors | ForEach-Object { $_.Message }) -join '; '
            throw "Unable to parse '$($ModuleFile.FullName)': $Messages"
        }

        $ExportNames = [System.Collections.Generic.List[string]]::new()
        $ExportCommands = $ModuleAst.FindAll({
                Param($Node)

                $Node -is [System.Management.Automation.Language.CommandAst] -and
                $Node.GetCommandName() -eq 'Export-ModuleMember'
            }, $true)

        foreach ($ExportCommand in $ExportCommands) {
            for ($Index = 0; $Index -lt $ExportCommand.CommandElements.Count; $Index++) {
                $Element = $ExportCommand.CommandElements[$Index]
                if ($Element -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                    continue
                }

                if ($Element.ParameterName -ne 'Function') {
                    continue
                }

                $ArgumentAst = $Element.Argument
                if ($null -eq $ArgumentAst -and ($Index + 1) -lt $ExportCommand.CommandElements.Count) {
                    $ArgumentAst = $ExportCommand.CommandElements[$Index + 1]
                }

                if ($null -eq $ArgumentAst) {
                    continue
                }

                foreach ($ExportName in (Get-ContractExportNames -Ast $ArgumentAst)) {
                    if (-not [String]::IsNullOrWhiteSpace($ExportName)) {
                        $ExportNames.Add($ExportName)
                    }
                }
            }
        }

        $UsingReferences = [System.Collections.Generic.List[string]]::new()
        foreach ($UsingStatement in $ModuleAst.UsingStatements) {
            if ($UsingStatement.UsingStatementKind -ne [System.Management.Automation.Language.UsingStatementKind]::Module) {
                continue
            }

            $UsingReferences.Add((Get-ContractUsingReference -UsingStatement $UsingStatement))
        }

        $ExportsByModule[$ModuleFile.Name] = @($ExportNames | Sort-Object -Unique)
        $UsingByModule[$ModuleFile.Name] = @($UsingReferences | Sort-Object -Unique)
    }

    return [ordered]@{
        Exports  = $ExportsByModule
        UsingMap = $UsingByModule
    }
}
