Using module ..\..\common\Environment.psm1
Using module ..\..\common\Logging.psm1
Using module ..\..\common\Scope.psm1
Using module ..\..\common\Utils.psm1
Using module ..\..\common\Temp.psm1


[CmdletBinding(SupportsShouldProcess)]
Param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$URL,

    [Parameter(HelpMessage = 'The pattern to find the executable in the zip file.')]
    [String]$ExecutablePattern,

    [Parameter(Position = 0, ValueFromRemainingArguments)]
    [String[]]$ExecArgs
)

function Get-Executable(
    [Parameter(Mandatory)]
    [String]$URL,

    [Parameter()]
    [String]$ExecutablePattern
) {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        if (-not $ExecutablePattern) {
            # If no pattern is specified, assume the executable is the last part of the URL and that it isn't zipped.
            [String]$Local:Executable = $URL.Split('/')[-1];
            Invoke-Info "No executable pattern specified, assuming executable is $Local:Executable";
            Invoke-WebRequest -Uri $URL -OutFile $Local:Executable -UseBasicParsing;
        } else {
            [String]$Local:OutFolder = $URL.Split('/')[-1].Split('.')[0];

            Invoke-Info "Downloading $URL to $Local:OutFolder.zip"
            Invoke-WebRequest -Uri $URL -OutFile "$Local:OutFolder.zip" -UseBasicParsing;

            # TODO :: Verify download completed successfully.

            Invoke-Info "Extracting $Local:OutFolder.zip to $Local:OutFolder";
            Expand-Archive -Path "$Local:OutFolder.zip" -DestinationPath $Local:OutFolder -Force;

            Invoke-Info "Looking for executable in $OutFolder\$ExecutablePattern";
            $Local:Executable = Get-Item -Path "$Local:OutFolder\$ExecutablePattern" | Select-Object -ExpandProperty FullName -First 1;
            if (-not $Local:Executable) {
                throw "Could not find executable matching pattern '$ExecutablePattern' in $Local:OutFolder";
            }
        }

        return $Local:Executable;
    }

}

function Invoke-Exec(
    [Parameter(Mandatory)]
    [String]$Executable,

    [String[]]$ExecutableArgs
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope; }

    process {
        Start-Process -FilePath "$Executable" -ArgumentList $ExecutableArgs -Wait -NoNewWindow;
    }

}

Invoke-RunMain $PSCmdlet {
    Invoke-WithinEphemeral {
        [String]$Local:Executable = Get-Executable -URL:$URL -ExecutablePattern:$ExecutablePattern;
        Invoke-Exec -Executable:$Local:Executable -ExecutableArgs:$ExecArgs;
    }
};
