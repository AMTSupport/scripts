Using module .\Logging.psm1
Using module .\ModuleUtils.psm1

class Flag {
    [String][ValidateNotNull()]$Context;
    [String][ValidateNotNull()]$FlagPath;

    Flag([String]$Context) {
        $this.Context = $Context;
        $this.FlagPath = Get-FlagPath -Context $Context;
    }

    [Boolean]Exists() {
        return Test-Path $this.FlagPath;
    }

    [Object]GetData() {
        if (-not $this.Exists()) {
            return $null;
        }

        return Get-Content -Path $this.FlagPath;
    }

    [Void]Set([Object]$Data) {
        New-Item -ItemType File -Path $this.FlagPath -Force;

        if ($null -ne $Data) {
            $Data | Out-File -FilePath $this.FlagPath -Force;
        }
    }

    [Void]Remove() {
        if (-not $this.Exists()) {
            return
        }

        Remove-Item -Path $this.FlagPath -Force;
    }
}

class RunningFlag: Flag {
    RunningFlag() : base('running') {}

    [Void]Set([Object]$Data) {
        if ($Data) {
            Invoke-Warn -Message 'Data is ignored for RunningFlag, only the PID of the running process is stored.'
        }

        [Int]$Local:CurrentPID = [System.Diagnostics.Process]::GetCurrentProcess().Id;
        if (-not (Get-Process -Id $Local:CurrentPID -ErrorAction SilentlyContinue)) {
            throw "PID $Local:CurrentPID is not a valid process";
        }

        ([Flag]$this).Set($Local:CurrentPID);
    }

    [Boolean]IsRunning() {
        if (-not $this.Exists()) {
            return $false;
        }

        # Check if the PID in the running flag is still running, if not, remove the flag and return false;
        [Int]$Local:RunningPID = $this.GetData();
        if (-not (Get-Process -Id $Local:RunningPID -ErrorAction SilentlyContinue)) {
            $this.Remove();
            return $false;
        }

        return $true;
    }
}

class RebootFlag: Flag {
    RebootFlag() : base('reboot') {}

    [Boolean]Required() {
        if (-not $this.Exists()) {
            return $false;
        }

        # Get the write time for the reboot flag file; if it was written before the computer started, we have reboot, return false;
        [DateTime]$Local:RebootFlagTime = (Get-Item $this.FlagPath).LastWriteTime;
        # Broken on first boot!
        [DateTime]$Local:StartTime = Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object -ExpandProperty LastBootUpTime;

        return $Local:RebootFlagTime -gt $Local:StartTime;
    }
}

function Get-FlagPath(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Context
) {
    process {
        # TODO - Make this dynamic based on the calling script's name

        [String]$Local:FlagFolder = "$($env:TEMP)\Flags";
        if (-not (Test-Path $Local:FlagFolder)) {
            Invoke-Verbose "Creating flag folder $Local:FlagFolder...";
            New-Item -ItemType Directory -Path $Local:FlagFolder;
        }

        [String]$Local:FlagPath = "$Local:FlagFolder\$Context.flag";
        $Local:FlagPath
    }
}

function Get-RebootFlag {
    [RebootFlag]::new();
}

function Get-RunningFlag {
    [RunningFlag]::new();
}

function Get-Flag([Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$Context) {
    [Flag]::new($Context);
}

Export-Types -Types ([Flag], [RunningFlag], [RebootFlag]) -Clobber;
Export-ModuleMember -Function Get-FlagPath,Get-RebootFlag,Get-RunningFlag,Get-Flag;
