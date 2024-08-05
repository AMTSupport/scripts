Using module ../src/common/Environment.psm1
Using module ../src/common/Logging.psm1

Using namespace System.Management.Automation.Language

[CmdletBinding()]
param()

Invoke-RunMain $PSCmdlet {
    $AvailableModules = Get-Module -ListAvailable;
    $AllFiles = Get-ChildItem -Path '..\' -Recurse -Include *.ps1,*.psm1;
    $ModulesToInstall = @();

    foreach ($File in $AllFiles) {
        $Ast = [Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null);
        [UsingStatementAst[]]$UsingStatements = $Ast.FindAll({
                param($ast)

                if (-not $ast -is [UsingStatementAst]) {
                    return $false;
                }
                [UsingStatementAst]$ast = $ast -as [UsingStatementAst];

                $ast.UsingStatementKind -eq 'Module' `
                    -and $ast.Name.Value -notlike '*.psm1' `
                    -and $ast.Name.Value -notlike '*.ps1';
            }, $True);

        # Check if the module is already installed
        # If it is check that it meets the version requirements
        foreach ($UsingStatement in $UsingStatements) {
            $ModuleName = $UsingStatement.Name.Value;

            $InstalledVersions = $AvailableModules | Where-Object { $_.Name -eq $ModuleName } | Select-Object -ExpandProperty Version;

            if ($null -ne $UsingStatement.ModuleSpecification) {
                [Version]$RequiredVersion = $UsingStatement.ModuleSpecification.SafeGetValue('RequiredVersion');
                [Version]$MinimumVersion = $UsingStatement.ModuleSpecification.SafeGetValue('MinimumVersion');
                [Version]$MaximumVersion = $UsingStatement.ModuleSpecification.SafeGetValue('MaximumVersion');

                if ($InstalledVersions) {
                    if ($RequiredVersion -and $InstalledVersions -notcontains $RequiredVersion) {
                        $ModulesToInstall += @{
                            Name            = $ModuleName;
                            RequiredVersion = $RequiredVersion;
                        };
                        continue;
                    }

                    $MeetsMinimum = $MinimumVersion -and ($InstalledVersions | Where-Object { $_ -ge $MinimumVersion }) -ge 1;
                    $MeetsMaximum = $MaximumVersion -and ($InstalledVersions | Where-Object { $_ -le $MaximumVersion }) -ge 1;

                    if ($MeetsMinimum -and $MeetsMaximum) {
                        continue;
                    }
                }

                $ModulesToInstall += @{
                    Name           = $ModuleName;
                    MinimumVersion = $MinimumVersion;
                    MaximumVersion = $MaximumVersion;
                }
            } else {
                if ($InstalledVersions) {
                    continue;
                }

                $ModulesToInstall += @{
                    Name = $ModuleName;
                };
            }
        }

        if ($ModulesToInstall) {
            $ModulesToInstall | ForEach-Object {
                $Name = $_.Name;
                $MinimumVersion = $_.MinimumVersion;
                $MaximumVersion = $_.MaximumVersion;
                $RequiredVersion = $_.RequiredVersion;

                if ($RequiredVersion) {
                    Invoke-Info "Installing module $Name with version $RequiredVersion";
                    Install-Module -Name $Name -RequiredVersion $RequiredVersion -Force -Scope CurrentUser;
                    return;
                }

                $VersionRange = @{};
                if ($MinimumVersion) {
                    $VersionRange | Add-Member -MemberType NoteProperty -Name 'MinimumVersion' -Value $MinimumVersion;
                }
                if ($MaximumVersion) {
                    $VersionRange | Add-Member -MemberType NoteProperty -Name 'MaximumVersion' -Value $MaximumVersion;
                }

                Invoke-Info "Installing module $Name with version range $($VersionRange | ConvertTo-Json)";
                Install-Module -Name $Name -Force -Scope CurrentUser @VersionRange;
            }
        }
    }
}
