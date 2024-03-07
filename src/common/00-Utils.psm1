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
.SYNOPSIS
    Get the value of an environment variable or save it if it does not exist.
.DESCRIPTION
    This function will get the value of an environment variable or save it if it does not exist.
    It will also validate the value if a test script block is provided.
    If the value does not exist, it will prompt the user for the value and save it as an environment variable,
    The value will be saved as a process environment variable.
.PARAMETER VariableName
    The name of the environment variable to get or save.
.PARAMETER LazyValue
    The script block to execute if the environment variable does not exist.
.PARAMETER Validate
    The script block to test the value of the environment variable or the lazy value.
.EXAMPLE
    Get-VarOrSave `
        -VariableName 'HUDU_KEY' `
        -LazyValue { Get-UserInput -Title 'Hudu API Key' -Question 'Please enter your Hudu API Key' };
.OUTPUTS
    System.String if the environment variable exists or the lazy value if it does not.
    null if the value didn't pass the validation.
#>
function Get-VarOrSave {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullorEmpty()]
        [String]$VariableName,

        [Parameter(Mandatory)]
        [ScriptBlock]$LazyValue,

        [Parameter()]
        [ScriptBlock]$Validate
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Value; }

    process {
        $Local:EnvValue = [Environment]::GetEnvironmentVariable($VariableName);

        if ($Local:EnvValue) {
            if ($Validate) {
                try {
                    if ($Validate.InvokeReturnAsIs($Local:EnvValue)) {
                        Invoke-Debug "Validated environment variable ${VariableName}: $Local:EnvValue";
                        return $Local:EnvValue;
                    } else {
                        Invoke-Error "Failed to validate environment variable ${VariableName}: $Local:EnvValue";
                        [Environment]::SetEnvironmentVariable($VariableName, $null, 'Process');
                    };
                } catch {
                    Invoke-Error "
                    Failed to validate environment variable ${VariableName}: $Local:EnvValue.
                    Due to reason ${$_.Exception.Message}".Trim();

                    [Environment]::SetEnvironmentVariable($VariableName, $null, 'Process');
                }
            } else {
                Invoke-Debug "Found environment variable $VariableName with value $Local:EnvValue";
                return $Local:EnvValue;
            }
        }

        while ($True) {
            try {
                $Local:Value = $LazyValue.InvokeReturnAsIs();

                if ($Validate) {
                    if ($Validate.InvokeReturnAsIs($Local:Value)) {
                        Invoke-Debug "Validated lazy value for environment variable ${VariableName}: $Local:Value";
                        break;
                    } else {
                        Invoke-Error "Failed to validate lazy value for environment variable ${VariableName}: $Local:Value";
                    }
                } else {
                    break;
                }
            } catch {
                Invoke-Error "Encountered an error while trying to get value for ${VariableName}.";
                return $null;
            }
        };


        [Environment]::SetEnvironmentVariable($VariableName, $Local:Value, 'Process');
        return $Local:Value;
    }
}

#region AST Helpers

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

#endregion

