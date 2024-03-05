<#
.DESCRIPTION
    This module contains utility functions that have no dependencies on other modules and can be used by any module.
#>

<#
.DESCRIPTION
    This function is used to measure the time it takes to execute a script block.

.EXAMPLE
    Measure-ElapsedTime {
        Start-Sleep -Seconds 5;
    }
#>
function Measure-ElaspedTime {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ScriptBlock]$ScriptBlock
    )

    process {
        [DateTime]$Local:StartAt = Get-Date;

        & $ScriptBlock;

        [TimeSpan]$Local:ElapsedTime = (Get-Date) - $Local:StartAt;
        return $Local:ElapsedTime * 10000; # Why does this make it more accurate?
    }
}

<#
.DESCRIPTION
    Try to transform the input object into an AST Object.
#>
function Get-Ast {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, HelpMessage = 'The input object to transform into an AST object.')]
        [ValidateNotNullOrEmpty()]
        [Object]$InputObject
    )

    process {
        $Local:Ast = switch ($InputObject) {
            { $_ -is [String] } {
                if (Test-Path -LiteralPath $_) {
                    $Local:Path = Resolve-Path -Path $_;
                    [System.Management.Automation.Language.Parser]::ParseFile($Local:Path.ProviderPath, [ref]$null, [ref]$null)
                } else {
                    [System.Management.Automation.Language.Parser]::ParseInput($_, [ref]$null, [ref]$null)
                }

                break
            }
            { $_ -is [System.Management.Automation.FunctionInfo] -or $_ -is [System.Management.Automation.ExternalScriptInfo] } {
                $InputObject.ScriptBlock.Ast
                break
            }
            { $_ -is [ScriptBlock] } {
                $_.Ast
                break
            }
            { $_ -is [System.Management.Automation.Language.Ast] } {
                $_
                break
            } Default {
                Invoke-Warn -Message "InputObject type not recognised: $($InputObject.gettype())";
                $null
            }
        }

        return $Local:Ast;
    }
}

<#
.DESCRIPTION
    Validate that this ast object has a return type that matches teh expected type.

.EXAMPLE
    [Boolean]$Local:HasCorrectReturnType = Test-ReturnType -Ast:$Ast -ValidTypes:'String','ScriptBlock';
#>
function Test-ReturnType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, HelpMessage = 'The AST object to test.')]
        [ValidateNotNullOrEmpty()]
        [Object]$InputObject,

        [Parameter(Mandatory, HelpMessage = 'The Valid Types to test against.')]
        [ValidateNotNullOrEmpty()]
        [String[]]$ValidTypes,

        [Parameter(HelpMessage = 'Allow the return type to be null.')]
        [Switch]$AllowNull
    )

    process {
        $Local:Ast = Get-Ast -InputObject $InputObject;
        $Local:AllReturnStatements = $Local:Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ReturnStatementAst] }, $true);
        foreach ($Local:ReturnStatement in $Local:AllReturnStatements) {
            [System.Management.Automation.Language.ExpressionAst]$Local:Expression = $Local:ReturnStatement.Pipeline.PipelineElements[0].expression;

            # TODO - Better handling of the variable path.
            if ($Local:Expression.VariablePath) {
                [String]$Local:VariableName = $Local:Expression.VariablePath.UserPath;

                # Try to resolve the variable and check its type.
                $Local:Variable = Get-Variable -Name:$Local:VariableName -ValueOnly -ErrorAction SilentlyContinue;

                if ($Local:Variable) {
                    [System.Reflection.TypeInfo]$Local:ReturnType = $Local:Variable.GetType();
                    [String]$Local:TypeName = $Local:ReturnType.Name;

                    if ($ValidTypes -contains $Local:TypeName) {
                        continue;
                    }
                } else {
                    Invoke-Debug -Message "Could not resolve the variable: $Local:VariableName.";
                    continue
                }
            } else {
                [System.Reflection.TypeInfo]$Local:ReturnType = $Local:Expression.StaticType;
                [String]$Local:TypeName = $Local:ReturnType.Name;

                Invoke-Debug "Return type: $Local:TypeName";

                if ($ValidTypes -contains $Local:TypeName -or ($AllowNull -and $Local:Expression.Extent.Text -eq '$null' -and $Local:ReturnType.Name -eq 'Object')) {
                    continue;
                }
            }

            $Local:Region = $Local:Expression.Extent;
            Invoke-Warn -Message "
            The return type of the script block is not valid. Expected: $($ValidTypes -join ', '); Actual: $Local:TypeName.
            At: $($Local:Region.StartLineNumber):$($Local:Region.StartColumnNumber) - $($Local:Region.EndLineNumber):$($Local:Region.EndColumnNumber)
            Text: $($Local:Region.Text)
            ";

            return $False;
        }

        return $True;
    }
}

<#
.DESCRIPTION
    Validate the parameters of a script block.
#>
function Test-Parameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, HelpMessage = 'The AST object to test.')]
        [ValidateNotNullOrEmpty()]
        [Object]$InputObject,

        [Parameter(Mandatory, HelpMessage = 'The Valid Types to test against.')]
        [ValidateNotNullOrEmpty()]
        [String[]]$ValidTypes
    )

    process {
        $Local:Ast = Get-Ast -InputObject $InputObject;
        $Local:AllParamStatements = $Local:Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ParameterAst] }, $true);
        foreach ($Local:ParamStatement in $Local:AllParamStatements) {
            [System.Management.Automation.Language.ParameterAst]$Local:Param = $Local:ParamStatement;
            [String]$Local:TypeName = $Local:Param.StaticType.Name;

            if ($ValidTypes -contains $Local:TypeName) {
                continue;
            }

            Invoke-Warn -Message "The parameter type of the script block is not valid. Expected: $($ValidTypes -join ', '); Actual: $Local:TypeName";
            return $False;
        }

        return $True;
    }
}
