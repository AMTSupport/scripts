#Requires -Version 7.1

Param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Company,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Endpoint = "hudu.amt.com.au"
)

function Invoke-Init {
    $Local:RepoRoot = ($MyInvocation.PSScriptRoot | Split-Path -Parent | Split-Path -Parent);
    $Local:CommonPath = Join-Path -Path $Local:RepoRoot -ChildPath 'src/common';

    if (($Local:RepoRoot | Split-Path -Leaf) -eq 'scripts' -and (Test-Path -Path $Local:CommonPath)) {
        Write-Host -ForegroundColor Green -Object "✅ Common modules found at $Local:CommonPath";
        Import-Module -Name $Local:CommonPath;
    } else {
        Write-Host -ForegroundColor Yellow -Object "⚠️ Common modules not found at $Local:CommonPath, cloning...";

        $Local:RepoName = 'scripts';
        $Local:RepoOwner = 'AMTSupport';
        $Local:RepoUrl = "https://github.com/$Local:RepoOwner/$Local:RepoName.git";

        $Local:RepoPath = Join-Path -Path (Join-Path -Path $env:TEMP -ChildPath $Local:RepoRoot) -ChildPath $Local:RepoName;
    }

    return

    If (-not (Get-Module -Name $Local:ModuleName -ListAvailable)) {
        Write-Host -ForegroundColor Yellow -Object "⚠️ $Local:ModuleName module not found, installing...";
        Install-Module -Name $Local:ModuleName -Scope CurrentUser -Force -RequiredVersion $Local:ModuleVersion;
    } else {
        Write-Host -ForegroundColor Green -Object "✅ $Local:ModuleName module found";
    }

    Import-Module -Name $Local:ModuleName -RequiredVersion $Local:ModuleVersion;
    Install-ModuleFromGithub -GitHubRepo 'AMTSupport/scripts' -Scope CurrentUser;
}

function Get-VarOrSave {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullorEmpty()]
        [String]$VariableName,

        [Parameter(Mandatory)]
        [ScriptBlock]$LazyValue,

        [ScriptBlock]$Test
    )

    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:Value; }

    process {
        $Local:EnvValue = [Environment]::GetEnvironmentVariable($VariableName);
        if ($Local:EnvValue) {
            if ($Test) {
                try {
                    $Test.InvokeReturnAsIs($Local:EnvValue);
                } catch {
                    Write-Host -ForegroundColor Red -Object "❌ Failed to validate environment variable ${VariableName}: $Local:EnvValue";
                    Write-Host -ForegroundColor Red -Object "❌ Reason: $($_.Exception.Message)";
                    throw "Failed to validate environment variable ${VariableName}: $Local:EnvValue";
                }
            }

            Write-Debug -Message "Found environment variable $VariableName with value $Local:EnvValue";
            return $Local:EnvValue;
        }

        try {
            $Local:Value = $LazyValue.InvokeReturnAsIs();
            Write-Debug -Message "Got value for ${VariableName}: $Local:Value";

            if ($Test) {
                try {
                    $Test.InvokeReturnAsIs($Local:Value);
                } catch {
                    throw "Failed to validate value for ${VariableName}: $_";
                }
            }
        } catch {
            Write-Error "Failed to get value for ${VariableName}";
        }

        [Environment]::SetEnvironmentVariable($VariableName, $Local:Value, 'Process');
        return $Local:Value;
    }
}

function Get-Expiration([Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$ApiKey) {
    $Local:Companies = Invoke-WebRequest -Headers @{ "x-api-key" = $ApiKey } -Uri "https://$Endpoint/api/v1/companies?page_size=1000" | ConvertFrom-Json;
    $Local:CompanyData = $Local:Companies | Where-Object { $_.name -like $Company -or $_.name -like $Company };

    if (-not $Local:CompanyData) {
        Write-Error -Message "Company $Company not found" -Category ObjectNotFound;
    }
}

function Update-Expiration {

}

function New-SecretValue {

}

function Remove-OldSecrets {

}

# Invoke-Init;
Import-Module $PSScriptRoot/../common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    [String]$Local:HuduKey = Get-VarOrSave -VariableName 'HUDU_KEY' -LazyValue {
        $Local:Input = Get-UserInput -Title 'Hudu API Key' -Question 'Please enter you''re Hudu API Key';
        if (-not $Local:Input) {
            throw 'Hudu Key cannot be empty';
        }

        return $Local:Input;
    };
}
