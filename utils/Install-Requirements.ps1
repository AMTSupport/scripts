Using module ../src/common/Environment.psm1
Using module ../src/common/Logging.psm1

Using namespace System.Management.Automation.Language

[CmdletBinding()]
param()

Invoke-RunMain $PSCmdlet {
    $AvailableModules = Get-Module -ListAvailable;
    $AllFiles = Get-ChildItem -Path '..\' -Recurse -Include *.ps1,*.psm1;
    $ModulesToInstall = @();

    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

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

        foreach ($UsingStatement in $UsingStatements) {
            $ModuleName = $UsingStatement.Name.Value;
            write-output "looking at using statement ($UsingStatement)"

            if ($null -ne $UsingStatement.ModuleSpecification) {
                $SafeHashtable = $UsingStatement.ModuleSpecification.SafeGetValue();
                $ModuleName = $SafeHashtable.ModuleName;
                [Version]$RequiredVersion = $SafeHashtable.RequiredVersion;
                [Version]$MinimumVersion = $SafeHashtable.ModuleVersion;
                [Version]$MaximumVersion = $SafeHashtable.MaximumVersion;

                $ModulesToInstall += @{
                    Name           = $ModuleName;
                    MinimumVersion = $MinimumVersion;
                    MaximumVersion = $MaximumVersion;
                }
            } else {
               $ModulesToInstall += @{
                    Name = $ModuleName;
                };
            }
        }
    }

    $MergedModules = @{}
    foreach ($Module in $ModulesToInstall) {
        if ($MergedModules[$Module.Name] -ne $null) {
            $Other = $Module[$Module.Name];
            if (-not ($Other.RequiredVersion -eq $null -and $Other.MinimumVersion -eq $null -and $Other.MaximumVersion -eq $null)) {
                Write-Error "module version merging not yet supported"
            } else {
                $MergedModules[$Module.Name] = $Module
            }
        } else {
            $MergedModules.add($Module.Name, $Module);
        }
    }

    $NeededModules = @{}
    foreach ($Module in $MergedModules.values) {
        $InstalledVersions = $AvailableModules | Where-Object { $_.Name -eq $Module.Name } | Select-Object -ExpandProperty Version;
        if ($InstalledVersions) {
            Invoke-Info "$($Module.Name) is already installed with versions $InstalledVersions, testing if valid"
            if (-not ($Module.RequiredVersion -or $Module.MinimumVersion -or $Module.MaximumVersion)) {
                Invoke-Verbose "Any version works!"
                continue
            }

            if ($Module.RequiredVersion -and $InstalledVersions -notcontains $Module.RequiredVersion) {
                Invoke-Verbose "Installed version(s) doesnt meet $($Module.RequiredVersion)"
                $NeededModules.add($Module.Name, $Module)
                continue;
            }

            $MeetsMinimum = ((-not $Module.MinimumVersion) -or ($InstalledVersions | Where-Object { $_ -ge $Module.MinimumVersion }).length -ge 1);
            $MeetsMaximum = ((-not $Module.MaximumVersion) -or ($InstalledVersions | Where-Object { $_ -le $Module.MaximumVersion }).length -ge 1);

            if ($MeetsMinimum -and $MeetsMaximum) {
                Invoke-Verbose "Installed version(s) range valid for declared range."
                continue;
            }

            Invoke-Verbose "Need to install $($Module | convertto-json)"
            $NeededModules.add($Module.Name, $Module)
        }
    }

    foreach ($Module in $NeededModules.values) {
        Invoke-Info "Installing $($Module.Name)"
        $Name = $Module.Name;
        $MinimumVersion = $Module.MinimumVersion;
        $MaximumVersion = $Module.MaximumVersion;
        $RequiredVersion = $Module.RequiredVersion;

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
