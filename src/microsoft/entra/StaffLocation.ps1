<#
.SYNOPSIS
    Used to setup and ensure that staff location is set up correctly.

.DESCRIPTION
    This script will run to create, reconfigure or test that a staff location is set up correctly.
    A staf location must have the following setup:
        - Security Group
        - Named Location
        - Conditional Access Policy
        - Intune Device Configuration Profile (Optional)
#>

Using module Microsoft.Graph.Identity.SignIns;
Using module Microsoft.Graph.Authentication;
Using module Microsoft.Graph.Groups;

Using namespace Microsoft.Graph.PowerShell.Models;
Using namespace System.Management.Automation;

[CmdletBinding()]
param()

Class CountryNames : System.Management.Automation.IValidateSetValuesGenerator {
    [String[]]GetValidValues() {
        return [CultureInfo]::GetCultures([System.Globalization.CultureTypes]::SpecificCultures) `
            | ForEach-Object { (New-Object System.Globalization.RegionInfo $_.Name).EnglishName } `
            | Select-Object -Unique | Sort-Object;
    }
}

function Test-SecurityGroup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [String]$GroupName,

        [Switch]$PassThru
    )

    [Boolean]$Local:Validated = $True;
    [MicrosoftGraphGroup]$Local:Group = Get-MgGroup -Filter "displayName eq '$GroupName'";
    if ($null -eq $Local:Group) {
        Invoke-Info "Security Group $GroupName does not exist.";
        $Local:Validated = $False;
    } else {
        Invoke-Info "Security Group $GroupName exists.";
    }

    if ($PassThru) {
        return $Local:Group, $Local:Validated;
    } else {
        return $Local:Validated;
    }
}

function Set-SecurityGroup {
    param (
        [MicrosoftGraphGroup]$InputObject,

        [Parameter(Mandatory)]
        [String]$GroupName
    )

    if (-not $InputObject) {
        [MicrosoftGraphUser[]]$Local:Users = Get-MgUser -Filter "-not startswith(displayName, 'zArchived')";
        [MicrosoftGraphUser[]]$Local:Members = @();
        while ($True) {
            $Local:User = Get-UserSelection `
                -Title 'Select a user' `
                -Question 'Please select a user to add to the security group.' `
                -Choices:$Local:Users;

            if ($Local:User) {
                $Local:Members += $Local:User;
            } else {
                break;
            }
        }

        $InputObject = New-MgGroup `
            -DisplayName:$GroupName `
            -MailEnabled:$True `
            -SecurityEnabled:$True `
            -Members:$Local:Members;

        Invoke-Info "Security Group $GroupName has been created."
    }

    Update-MgGroup -InputObject:$InputObject `
        -DisplayName:$GroupName `
        -MailEnabled:$True `
        -SecurityEnabled:$True `
        -MailNickname:$GroupName `
        -Description:"Staff Security Group";

    Invoke-Info "Security Group $GroupName has been updated.";

    return $InputObject;
}

function Test-NamedLocation {
    param (
        [String]$LocationName,

        [String[]]$Countries,

        [Switch]$PassThru
    )

    [Boolean]$Local:Validated = $True;
    [MicrosoftGraphNamedLocation]$Local:Location = New-MgIdentityConditionalAccessNamedLocation -DisplayName:$LocationName;
    if ($null -eq $Local:Location) {
        Invoke-Info "Named Location $LocationName does not exist.";
        $Local:Validated = $False;
    } else {
        Invoke-Info "Named Location $LocationName exists.";
    }



    if ($PassThru) {
        return $Local:Location, $Local:Validated;
    } else {
        return $Local:Validated;
    }
}

function Set-NamedLocation {
    param(
        [MicrosoftGraphNamedLocation]$InputObject,

        [Parameter(Mandatory)]
        [String]$LocationName,

        [String[]]$Countries
    )

    New-MgIdentityConditionalAccessNamedLocation
}

function Test-ConditionalAccessPolicy {
    param (
        [String]$PolicyName,

        [Switch]$PassThru
    )

    [Boolean]$Local:Validated = $True;
    $Local:Policy = Get-MgIdentityConditionalAccessPolicy

    if ($PassThru) {
        return $Local:Policy, $Local:Validated;
    } else {
        return $Local:Validated;
    }
}

function Set-ConditionalAccessPolicy {
    New-MgIdentityConditionalAccessPolicy
}

[ScriptBlock]$Local:ScriptBlock = {
    [CmdletBinind()]
    param(
        [Parameter(Mandatory = $True)]
        [ValidateSet('Test', 'Set')]
        [String]$Action,

        [Parameter(Mandatory)]
        [ValidateSet([CountryNames])]
        [String[]]$Countries
    )

    Connect-Service -Services:Graph -Scopes:Policy.Read.All, Policy.ReadWrite.ConditionalAccess;

    # [String]$Local:Suffix = Get-UserInput `
    #     -Title 'What is the location called' `
    #     -Question 'Please enter the name which will be used to create the security group, named location and conditional access policy.';

    [String[]]$Local:PossibleCountries = [CultureInfo]::GetCultures([System.Globalization.CultureTypes]::SpecificCultures) `
        | ForEach-Object { (New-Object System.Globalization.RegionInfo $_.Name).EnglishName } `
        | Select-Object -Unique | Sort-Object;

    Invoke-Info 'Please select the primary country first and then select the secondary countries.';
    [String[]]$Local:Countries = @();
    while ($True) {
        $Local:Country = Get-UserSelection `
            -Title 'Select a country' `
            -Question 'Please select a country to allow access from.' `
            -Choices:$Local:PossibleCountries;

        if ($Local:Country) {
            $Local:Countries += $Local:Country;
        } else {
            break;
        }
    };

    [String]$Local:PrimaryCountry = $Local:Countries[0];
    [String]$Local:GroupName = "Staff - $Local:PrimaryCountry";
    [String]$Local:LocationName = "Staff - $Local:PrimaryCountry";
    [String]$Local:PolicyName = "Staff - $Local:PrimaryCountry";

    switch ($Action) {
        'Test' {
            [Boolean]$Local:ValidatedGroup = Test-SecurityGroup -GroupName:$Local:GroupName;
            [Boolean]$Local:ValidatedLocation = Test-NamedLocation -LocationName:$Local:LocationName -Countries:$Local:Countries;
            [Boolean]$Local:ValidatedPolicy = Test-ConditionalAccessPolicy -PolicyName:$Local:PolicyName;

            if ($Local:ValidatedGroup -and $Local:ValidatedLocation -and $Local:ValidatedPolicy) {
                Invoke-Info "Staff Location is setup correctly.";
            } else {
                Invoke-Info "
                Component Test Results:
                - Security Group: $Local:GroupName
                - Named Location: $Local:LocationName
                - Conditional Access Policy: $Local:PolicyName
                ".Trim();
                Invoke-Info "Staff Location is not setup correctly.";
                Invoke-Info "Please run the script with the 'Set' action to create the missing components.";
            }
        }
        'Set' {
            ([MicrosoftGraphGroup]$Local:Group, [Boolean]$Local:Validated) = Test-SecurityGroup -GroupName:$Local:GroupName -PassThru;
            if (-not $Local:Validated) {
                $Local:Group = $Local:Group | Set-SecurityGroup -GroupName:$Local:GroupName;
            }

            ($Local:NamedLocation, $Local:Validated) = Test-NamedLocation -LocationName:$Local:LocationName -Countries:$Local:Countries -PassThru;
            if (-not $Local:Validated) {
                $Local:NamedLocation = $Local:NamedLocation | Set-NamedLocation -Countries:$Local:Countries;
            }

            ($Local:Policy, $Local:Validated) = Test-ConditionalAccessPolicy -PolicyName:$Local:PolicyName -PassThru;
            if (-not $Local:Validated) {
                $Local:Policy = $Local:Policy | Set-ConditionalAccessPolicy -PolicyName:$Local:PolicyName -NamedLocation:$Local:NamedLocation -SecurityGroup:$Local:Group;
            }
        }
    }
};

# Register-ArgumentCompleter -CommandName:($PSCommandPath | Split-Path -Leaf) -ScriptBlock $Local:ScriptBlock
Import-Module $PSScriptRoot/../../common/00-Environment.psm1;
Invoke-RunMain $MyInvocation -Main:$Local:ScriptBlock;

dynamicparam {
    Start-Sleep -Seconds 15;

    $Parameters = $Local:ScriptBlock.Ast.ParamBlock.Parameters;
    if ($Parameters.Count -eq 0) {
        Write-Host "No parameters found.";
        return;
    } else {
        Write-Host "Found $($Parameters.Count) parameters.";
    }

    $RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary;

    foreach ($Param in $Parameters) {
        $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute];

        foreach ($Attribute in $Param.Attributes) {
            $AttributeSet = New-Object "System.Management.Automation.$($Attribute.TypeName)Attribute";
            foreach ($Argument in $Attribute.NamedArguments) {
                if ($Argument.ExpressionOmmited) {
                    # Assume its a switch parameter
                    $AttributeSet.($Argument.ArgumentName) = $True;
                } else {
                    # Invoke the expression to get the value
                    $AttributeSet.($Argument.ArgumentName) = Invoke-Expression $Attribute.Argument.Extent.Text;
                }
            }

            $AttributeCollection.Add($AttributeSet);
        }

        $ParameterName = $Param.Name.VariablePath.UserPath;
        $ParameterType = $Param.StaticType;
        $RuntimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new($ParameterName, $ParameterType, $AttributeCollection);
        $RuntimeParameterDictionary.Add($ParameterName, $RuntimeParameter);
    }

    return $RuntimeParameterDictionary
}
# dynamicparam {
#     [RuntimeDefinedParameterDictionary]$Parameters = [RuntimeDefinedParameterDictionary]::new();

#     $scriptParameters = $null
#     if ($PSCmdlet.ParameterSetName -eq "Name") {
#         $Script = $base.Client.GetScriptByName($Name).ToResult()
#         if ($Script -eq $null) {
#             throw New-Object System.Exception("Unknown script: $Name")
#         }
#         $scriptParameters = $base.Client.GetScriptParameters($Script).ToResult()
#     } elseif ($PSCmdlet.ParameterSetName -eq "Id") {
#         $Script = $base.Client.GetScript($Id).ToResult()
#         if ($Script -eq $null) {
#             throw New-Object System.Exception("Unknown script: $Id")
#         }
#         $scriptParameters = $base.Client.GetScriptParameters($Script).ToResult()
#     } else {
#         if ($Script -eq $null) {
#             throw New-Object System.Exception("Script not specified or passed by pipeline.")
#         }
#         if ($Script.Id -eq 0L) {
#             $Script = $base.Client.GetScriptByName($Script.FullPath).ToResult()
#             if ($Script -eq $null) {
#                 throw New-Object System.Exception("Unknown script: $($Script.FullPath)")
#             }
#         }
#         $scriptParameters = $base.Client.GetScriptParameters($Script).ToResult()
#     }
#     if ($scriptParameters -eq $null) {
#         throw New-Object System.Exception("Script not found.")
#     }
#     $scriptParameters = $scriptParameters.ToArray()

#     $assemblies = [System.AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object { $_.GetTypes() };
#     $parameters = @{};

#     foreach ($item in ($scriptParameters | Group-Object -Property Name)) {
#         $scriptParameter = $item.Group[0]
#         $type = [object]
#         $typeName = if ($scriptParameter.Type -eq "System.Management.Automation.PSCredential") { "PowerShellUniversal.Variable" } else { $scriptParameter.Type }

#         try {
#             $type = ($assemblies | Where-Object { $_.FullName -eq $typeName }).BaseType
#         } catch {
#             Write-Warning $_.Exception.Message
#         }

#         $runtimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($scriptParameter.Name, $type, @(New-Object System.Collections.ObjectModel.Collection[System.Attribute](@(New-Object System.Management.Automation.ParameterAttribute))))
#         $parameters[$scriptParameter.Name] = $runtimeParameter
#     }

#     return $parameters
# }
