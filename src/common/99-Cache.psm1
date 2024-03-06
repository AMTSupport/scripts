[Int]$Script:FAILED_FOLDER_CREATION = Register-ExitCode 'Failed to create the cache folder.';
[Int]$Script:FAILED_FILE_CREATION = Register-ExitCode 'Failed to create the cache file.';
[Int]$Script:FAILED_FILE_REMOVAL = Register-ExitCode 'Failed to remove the cache file.';
[String]$Script:Folder = $env:TEMP | Join-Path -ChildPath 'PSCache';

function Get-CachedContent {
    param(
        [Parameter(Mandatory, HelpMessage="The unique name of the cache file.")]
        [String]$Name,

        [Parameter(HelpMessage="The maximum age of the cache file.")]
        [TimeSpan]$MaxAge,

        [Parameter(HelpMessage = 'A Custom script block to determine if the cached content is still valid.')]
        [ScriptBlock]$IsValidBlock,

        [Parameter(Mandatory, HelpMessage="The script block which creates the content to be cached if needed, this should return a JSON object.")]
        [ScriptBlock]$CreateBlock,

        [Parameter()]
        [ScriptBlock]$WriteBlock,

        [Parameter(Mandatory, HelpMessage="The script block to parse the cached content.")]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]$ParseBlock,

        [Parameter(HelpMessage="Don't use the cached response, use the CreateBlock.")]
        [Switch]$NoCache
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:CacheContent; }

    process {
        [HashTable]$Local:Params = $PSBoundParameters;
        $Local:Params.Remove('ParseBlock');
        # $Local:FilteredParams = $Local:Params.GetEnumerator() | Where-Object { $null -ne $_.Value };

        Invoke-Debug "Cache parameters: $($PSBoundParameters | Out-String)"
        [String]$Local:CachePath = Get-CachedLocation @Local:Params;

        $Local:RawContent = Get-Content -Path $Local:CachePath -Raw;
        $Local:CacheContent = $ParseBlock.InvokeReturnAsIs(@($Local:RawContent));

        return $Local:CacheContent;
    }
}

function Get-CachedLocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, HelpMessage = 'The unique name of the cache file.')]
        [ValidateNotNullOrEmpty()]
        [String]$Name,

        [Parameter(HelpMessage = 'The maximum age of the cache file.')]
        [TimeSpan]$MaxAge,

        [Parameter(HelpMessage = 'A Custom script block to determine if the cached content is still valid.')]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            [System.Management.Automation.Language.Ast]$Local:Ast = $_.Ast;

            if (-not ($Local:Ast.ParamBlock.Parameters.Count -eq 1)) {
                Invoke-Error 'The script block should have one parameter.';
                return $False;
            }

            if (-not (Test-ReturnType -InputObject:$_ -ValidTypes:@('Boolean'))) {
                Invoke-Error 'The script block should return a boolean value.';
                return $False;
            }

            return $True;
        })]
        [ScriptBlock]$IsValidBlock,

        [Parameter(Mandatory, HelpMessage = 'The script block which creates the content to be cached if needed, this should return a JSON object.')]
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

        [Parameter(HelpMessage = 'The script block used to write the content to the cache file.')]
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
                [ValidateNotNullOrEmpty()]
                [Object]$Content
            )

            $Content | Set-Content -Path $Path -Encoding UTF8;
        },

        [Parameter(HelpMessage = "Don't use the cached response, use the CreateBlock.")]
        [Switch]$NoCache
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:CachePath; }

    process {
        [String]$Local:CachePath = $Script:Folder | Join-Path -ChildPath "Cached-$Name";

        if (-not (Test-Path -Path $Script:Folder)) {
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

            if ($MaxAge) {
                [TimeSpan]$Local:CacheAge = (Get-Date) - (Get-Item -Path $Local:CachePath).LastWriteTime;
                Invoke-Debug "Cache has a maximum age of $($MaxAge.TotalMinutes) minutes, currently $($Local:CacheAge.TotalMinutes) minutes old.";

                if ($NoCache -or $Local:CacheAge -gt $MaxAge) {
                    Remove-Cache -CachePath $Local:CachePath;
                }
            } elseif ($IsValidBlock) {
                if (-not ($IsValidBlock.InvokeReturnAsIs(@($Local:CachePath)))) {
                    Invoke-Verbose 'Cache is no longer valid, removing and re-creating.';
                    Remove-Cache -CachePath $Local:CachePath;
                }
            } else {
                Invoke-Verbose 'No cache validation method provided, skipping validation and re-creating.';
                Remove-Cache -CachePath $Local:CachePath;
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
