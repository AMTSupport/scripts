Using module .\Logging.psm1
Using module .\Scope.psm1
Using module .\Exit.psm1
Using module .\Utils.psm1

[Int]$Script:FAILED_FOLDER_CREATION = Register-ExitCode 'Failed to create the cache folder.';
[Int]$Script:FAILED_FILE_CREATION = Register-ExitCode 'Failed to create the cache file.';
[Int]$Script:FAILED_FILE_REMOVAL = Register-ExitCode 'Failed to remove the cache file.';
[String]$Script:Folder = [System.IO.Path]::GetTempPath() | Join-Path -ChildPath 'PSCache';

function Get-CachedContent {
    param(
        [Parameter(Mandatory, HelpMessage = 'The unique name of the cache file.')]
        [String]$Name,

        [Parameter(HelpMessage = 'The maximum age of the cache file.')]
        [TimeSpan]$MaxAge,

        [Parameter(HelpMessage = 'A Custom script block to determine if the cached content is still valid.')]
        [ScriptBlock]$IsValidBlock,

        [Parameter(Mandatory, HelpMessage = 'The script block which creates the content to be cached if needed, this should return a JSON object.')]
        [ScriptBlock]$CreateBlock,

        [Parameter()]
        [ScriptBlock]$WriteBlock,

        [Parameter(HelpMessage = 'The script block to parse the cached content.')]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]$ParseBlock = {
            param($raw) return ConvertFrom-Json $raw -AsHashtable;
        },

        [Parameter(HelpMessage = "Don't use the cached response, use the CreateBlock.")]
        [Switch]$NoCache
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:CacheContent; }

    process {
        [HashTable]$Local:Params = $PSBoundParameters;
        $Local:Params.Remove('ParseBlock');

        [String]$Local:CachePath = Get-CachedLocation @Local:Params;

        $Local:RawContent = Get-Content -Path $Local:CachePath -Raw;
        $Local:CacheContent = $ParseBlock.InvokeReturnAsIs(@($Local:RawContent));

        return $Local:CacheContent;
    }
}

<#
.SYNOPSIS
    Get the location of a cached file, creating it if needed.

.DESCRIPTION
    This function checks if the cache file exists and is valid. If it doesn't exist, it calls the CreateBlock to generate the file.
    The cache file is considered valid if it exists, is not older than MaxAge, and if provided, the IsValidBlock returns true.

.PARAMETER Name
    The unique name of the cache file, used to generate the file path.

.PARAMETER MaxAge
    The maximum age of the cache file.
    If left empty, the cache file will always be considered valid by age.

.PARAMETER IsValidBlock
    A script block that determines if the cached content is still valid.
    This should have one parameter: Path and return a boolean value.

.PARAMETER CreateBlock
    A script block that creates the content to be cached;
    If WriteBlock not customised this will write verbatim into the cache file.

.PARAMETER WriteBlock
    A script block that writes the content to the cache file;
    This should have two parameters: Path and Content.

.PARAMETER NoCache
    Indicates that the cache should be ignored and to recreate the content.
#>
function Get-CachedLocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Name,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [TimeSpan]$MaxAge,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                [System.Management.Automation.Language.Ast]$Local:Ast = $_.Ast;

                if (-not ($Local:Ast.ParamBlock.Parameters.Count -eq 1)) {
                    Invoke-Error 'The script block should have one parameter.';
                    return $False;
                }

                if (-not (Test-ReturnType -InputObject:$_ -ValidTypes @([Boolean]))) {
                    Invoke-Error 'The script block should return a boolean value.';
                    return $False;
                }

                return $True;
            })]
        [ScriptBlock]$IsValidBlock,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                [System.Management.Automation.Language.Ast]$Local:Ast = $_.Ast;

                if (-not ($Local:Ast.ParamBlock.Parameters.Count -eq 0)) {
                    Invoke-Error 'The script block should not have any parameters.';
                    return $False;
                }

                if (($Local:Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ReturnStatementAst] }, $True).Count -lt 1)) {
                    Invoke-Error 'The script block should return a value.';
                    return $False;
                }

                return $True;
            })]
        [ScriptBlock]$CreateBlock,

        [Parameter()]
        [ValidateScript({
                [System.Management.Automation.Language.Ast]$Local:Ast = $_.Ast;

                if (-not ($Local:Ast.ParamBlock.Parameters.Count -eq 2)) {
                    Invoke-Error 'The script block should have two parameters.';
                    return $false;
                }

                return $true;
            })]
        [ScriptBlock]$WriteBlock = {
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [String]$Path,

                [Parameter(Mandatory)]
                [Object]$Content
            )

            $Content | Set-Content -Path $Path -Encoding UTF8;
        },

        [Parameter()]
        [Switch]$NoCache
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:CachePath; }

    process {
        [String]$Local:CachePath = $Script:Folder | Join-Path -ChildPath "Cached-$Name";

        if (-not (Test-Path -Path $Script:Folder)) {
            Invoke-Verbose 'Cache folder not found, creating one...';

            try {
                New-Item -Path $Script:Folder -ItemType Directory | Out-Null;
            } catch {
                Invoke-FailedExit -ExitCode $Script:FAILED_FOLDER_CREATION -ErrorRecord $_;
            }
        }

        if (Test-Path -Path $Local:CachePath) {
            function Remove-Cache([String]$CachePath) {
                Invoke-Debug "Removing cache file at $CachePath.";

                try {
                    $ErrorActionPreference = 'Stop';

                    Remove-Item -Path $CachePath | Out-Null;
                } catch {
                    Invoke-FailedExit -ExitCode $Script:FAILED_FILE_REMOVAL -ErrorRecord $_;
                }
            }

            if ($NoCache) {
                Remove-Cache -CachePath $Local:CachePath;
            } elseif ($MaxAge) {
                [TimeSpan]$Local:CacheAge = (Get-Date) - (Get-Item -Path $Local:CachePath).LastWriteTime;
                Invoke-Debug "Cache has a maximum age of $($MaxAge.TotalMinutes) minutes, currently $($Local:CacheAge.TotalMinutes) minutes old.";

                if ($Local:CacheAge -gt $MaxAge) {
                    Remove-Cache -CachePath $Local:CachePath;
                }
            } elseif ($IsValidBlock) {
                if (-not ($IsValidBlock.InvokeReturnAsIs(@($Local:CachePath)))) {
                    Invoke-Verbose 'Cache is no longer valid, removing and re-creating.';
                    Remove-Cache -CachePath $Local:CachePath;
                }
            } else {
                Invoke-Verbose 'No cache validation method provided, assuming valid.';
            }
        }

        if (-not (Test-Path -Path $Local:CachePath)) {
            Invoke-Verbose 'Cache file not found, creating a new one.';
            $Local:CacheContent = & $CreateBlock;

            try {
                $WriteBlock.InvokeReturnAsIs(@($Local:CachePath, $Local:CacheContent));
            } catch {
                Invoke-FailedExit -ExitCode $Script:FAILED_FILE_CREATION -ErrorRecord $_;
            }
        }

        return $Local:CachePath;
    }
}

Export-ModuleMember -Function Get-CachedContent, Get-CachedLocation;
