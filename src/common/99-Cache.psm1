[Int]$Script:FAILED_FOLDER_CREATION = Register-ExitCode 'Failed to create the cache folder.';
[Int]$Script:FAILED_FILE_CREATION = Register-ExitCode 'Failed to create the cache file.';
[Int]$Script:FAILED_FILE_REMOVAL = Register-ExitCode 'Failed to remove the cache file.';
[String]$Script:Folder = $env:TEMP | Join-Path -ChildPath 'PSCache';

function Get-CachedContent {
    param(
        [Parameter(Mandatory, HelpMessage="The unique name of the cache file.")]
        [ValidateNotNullOrEmpty()]
        [String]$Name,

        [Parameter(Mandatory, HelpMessage="The script block which creates the content to be cached if needed, this should return a JSON object.")]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]$CreateBlock,

        [Parameter(Mandatory, HelpMessage="The script block to parse the cached content.")]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]$ParseBlock,

        [Parameter(Mandatory, HelpMessage="The maximum age of the cache file.")]
        [TimeSpan]$MaxAge,

        [Parameter(HelpMessage="Don't use the cached response, use the CreateBlock.")]
        [Switch]$NoCache
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:File; }

    process {
        [String]$Local:CachePath = $Script:Folder | Join-Path -ChildPath "Cached-$Name.json";

        if (-not (Test-Path -Path $Script:Folder)) {
            try {
                New-Item -Path $Script:Folder -ItemType Directory | Out-Null;
            } catch {
                Invoke-FailedExit -ExitCode $Script:FAILED_FOLDER_CREATION -ErrorRecord $_;
            }
        }

        if (Test-Path -Path $Local:CachePath) {
            [TimeSpan]$Local:CacheAge = (Get-Date) - (Get-Item -Path $Local:CachePath).CreationTime;

            if ($NoCache -or $Local:CacheAge -gt $MaxAge) {
                Invoke-Verbose "Cache is $Local:CacheAge minutes old, removing and re-creating.";
                try {
                    Remove-Item -Path $Local:CachePath | Out-Null;
                } catch {
                    Invoke-FailedExit -ExitCode $Script:FAILED_FILE_REMOVAL -ErrorRecord $_;
                }
            } else {
                Invoke-Verbose "Cache is less than $($MaxAge.Minutes) minutes old, skipping create block.";
            }
        }

        if (-not (Test-Path -Path $Local:CachePath)) {
            Invoke-Verbose 'Cache file not found, creating a new one.';
            $Local:CacheContent = & $CreateBlock;

            try {
                $Local:CacheContent | Out-File -FilePath $Local:CachePath -Encoding UTF8;
            } catch {
                Invoke-FailedExit -ExitCode $Script:FAILED_FILE_CREATION -ErrorRecord $_;
            }
        }

        $Local:CacheContent = Get-Content -Path $Local:CachePath | & $ParseBlock;
        return $Local:CacheContent;
    }
}

