#Requires -Version 5.1
# Requires -RunAsAdministrator

<#
.TODO
    Implement Hash checking for the downloaded file.
#>

# Section start :: Set Variables

$RegexMatcher = "^(?<User>[^:]+):(?<Repository>[^:]+):(?<Version>[^:]+)$"

# Section end :: Set Variables

# Section start :: Classes

Class Repository {
    [String]$User
    [String]$Repo
    [String]$Version
    [String]$URL
    [String]$Path

    Repository([String]$User, [String]$Repo, [String]$Version) {
        $this.User = $User
        $this.Repo = $Repo
        $this.Version = $Version
        $this.URL = "https://api.github.com/repos/${User}/${Repo}/releases/${Version}"

        Write-Host "Repository URL is $($this.URL)"
    }

    [Void] EnsureLatest() {
        $request = (Invoke-RestMethod -Uri $this.URL)

        if ($request.assets.Count -eq 0) {
            Write-Host "No assets found for $($this.User)/$($this.Repo) version $($this.Version)"
            exit 1
        }

        $asset = ($request.assets | Where-Object { $_.content_type -eq "application/x-msdownload" })
        if ($null -eq $asset) {
            Write-Host "No asset found for $($this.User)/$($this.Repo) version $($this.Version)"
            exit 1
        }

        $updatedAt = $asset.updated_at.Replace(':', '-')
        $assetName = $asset.name.Replace(".exe", '')
        $assetURL = $asset.browser_download_url

        Write-Host "Downloading $($this.User)/$($this.Repo) version $($this.Version) from $($assetURL)"
        $this.Path = "$($env:TEMP)\RemoteRunner\$assetName-$updatedAt.exe"

        if (Test-Path -Path $this.Path) {
            Write-Host "File already exists at $($this.Path)"
            return
        }

        if (-not (Test-Path -Path $this.Path)) {
            Write-Host "Creating directory $($this.Path | Split-Path -Parent)"
            New-Item -Path ($this.Path | Split-Path -Parent) -ItemType Directory -Force
        }

        Write-Host "Downloading to $($this.Path)"
        Invoke-WebRequest -Uri $assetURL -OutFile $this.Path
    }

    [Void] Execute([String]$parsedArgs = [String]::Empty) {
        Write-Host "Executing ``$($this.Path)`` with arguments ``$parsedArgs``"

        & "$($this.Path)" "$($parsedArgs)" | %{
            if ($_ -match 'OK')
            { Write-Host $_ -f Green }
            elseif ($_ -match 'FAIL|ERROR')
            { Write-Host $_ -f Red }
            else
            { Write-Host $_ }
         }
    }
}

# Section end :: Classes

if (($args | Where-Object { $_ -match $RegexMatcher }).Count -eq 0) {
    Write-Host "Invalid arguments. Expected format is ./RemoteRunner.ps1 User:Repository:Version -- [args]"
    exit 1
}

if ($MyInvocation.Line.Contains(" -- ")) {
    $parsedArgs = $MyInvocation.Line.SubString($MyInvocation.Line.IndexOf(" -- ") + 4).Trim()
    Write-host "Parsing additional arguments to executable: ``$parsedArgs``"
} else {
    Write-host "Parsing no additional arguments to executable."
}

$repo = [Repository]::new($Matches.User, $Matches.Repository, $Matches.Version)
$repo.EnsureLatest()
$repo.Execute($parsedArgs)

