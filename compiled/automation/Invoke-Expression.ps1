#Requires -Version 5.1

Param(
    [Parameter(Mandatory)]
    [ScriptBlock]$Expression
)
$Global:CompiledScript = $true;
$Global:EmbededModules = [ordered]@{
    "00-Environment" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
		[System.Boolean]$Global:ScriptRestarted = $False;
		[System.Boolean]$Global:ScriptRestarting = $False;
		[System.Collections.Generic.List[String]]$Script:ImportedModules = [System.Collections.Generic.List[String]]::new();
		[HashTable]$Global:Logging = @{
		    Loaded      = $false;
		    Error       = $True;
		    Warning     = $True;
		    Information = $True;
		    Verbose     = $VerbosePreference -ne 'SilentlyContinue';
		    Debug       = $DebugPreference -ne 'SilentlyContinue';
		};
		function Invoke-WithLogging {
		    Param(
		        [Parameter(Mandatory)]
		        [ValidateNotNull()]
		        [ScriptBlock]$HasLoggingFunc,
		        [Parameter(Mandatory)]
		        [ValidateNotNull()]
		        [ScriptBlock]$MissingLoggingFunc
		    )
		    process {
		        if ($Global:Logging.Loaded) {
		            $HasLoggingFunc.InvokeReturnAsIs();
		        }
		        else {
		            $MissingLoggingFunc.InvokeReturnAsIs();
		        }
		    }
		}
		function Invoke-EnvInfo {
		    Param(
		        [Parameter(Mandatory)]
		        [ValidateNotNull()]
		        [String]$Message,
		        [Parameter()]
		        [ValidateNotNullOrEmpty()]
		        [String]$UnicodePrefix
		    )
		    Invoke-WithLogging `
		        -HasLoggingFunc { if ($UnicodePrefix) { Invoke-Info $Message $UnicodePrefix; } else { Invoke-Info -Message:$Message; } } `
		        -MissingLoggingFunc { Write-Host -ForegroundColor Cyan -Object $Message; };
		}
		function Invoke-EnvVerbose {
		    Param(
		        [Parameter(Mandatory)]
		        [ValidateNotNull()]
		        [String]$Message,
		        [Parameter()]
		        [ValidateNotNullOrEmpty()]
		        [String]$UnicodePrefix
		    )
		    Invoke-WithLogging `
		        -HasLoggingFunc { if ($UnicodePrefix) { Invoke-Verbose $Message $UnicodePrefix; } else { Invoke-Verbose -Message:$Message; } } `
		        -MissingLoggingFunc { Write-Verbose -Message $Message; };
		}
		function Invoke-EnvDebug {
		    Param(
		        [Parameter(Mandatory)]
		        [ValidateNotNull()]
		        [String]$Message,
		        [Parameter()]
		        [ValidateNotNullOrEmpty()]
		        [String]$UnicodePrefix
		    )
		    Invoke-WithLogging `
		        -HasLoggingFunc { if ($UnicodePrefix) { Invoke-Debug $Message $UnicodePrefix } else { Invoke-Debug -Message:$Message; }; } `
		        -MissingLoggingFunc { Write-Debug -Message $Message; };
		}
		function Get-OrFalse {
		    Param(
		        [Parameter(Mandatory)]
		        [ValidateNotNull()]
		        [HashTable]$HashTable,
		        [Parameter(Mandatory)]
		        [ValidateNotNullOrEmpty()]
		        [String]$Key
		    )
		    process {
		        if ($HashTable.ContainsKey($Key)) {
		            return $HashTable[$Key];
		        }
		        else {
		            return $false;
		        }
		    }
		}
		function Test-OrGetBooleanVariable {
		    Param(
		        [Parameter(Mandatory)]
		        [ValidateNotNull()]
		        [String]$Name
		    )
		    process {
		        if (Test-Path Variable:Global:$Name) {
		            return Get-Variable -Scope Global -Name $Name -ValueOnly;
		        }
		        else {
		            return $false;
		        }
		    }
		}
		function Test-IsCompiledScript {
		    Test-OrGetBooleanVariable -Name 'CompiledScript';
		}
		function Test-IsRestartingScript {
		    Test-OrGetBooleanVariable -Name 'ScriptRestarting';
		}
		function Test-IsRestartedScript {
		    Test-OrGetBooleanVariable -Name 'ScriptRestarted';
		}
		function Test-ExplicitlyCalled {
		    Param(
		        [Parameter(Mandatory)]
		        [ValidateNotNull()]
		        [System.Management.Automation.InvocationInfo]$Invocation
		    )
		    process {
		        $Global:Invocation = $Invocation;
		        if ($Invocation.CommandOrigin -eq 'Runspace' -and ($Invocation.InvocationName | Split-Path -Leaf) -eq $Invocation.MyCommand.Name) {
		            return $True;
		        }
		        return $True;
		    }
		}
		function Test-IsNableRunner {
		    $WindowName = $Host.UI.RawUI.WindowTitle;
		    if (-not $WindowName) { return $False; };
		    return ($WindowName | Split-Path -Leaf) -eq 'fmplugin.exe';
		}
		function Invoke-Setup {
		    $PSDefaultParameterValues['*:ErrorAction'] = 'Stop';
		    $PSDefaultParameterValues['*:WarningAction'] = 'Continue';
		    $PSDefaultParameterValues['*:InformationAction'] = 'Continue';
		    $PSDefaultParameterValues['*:Verbose'] = $Global:Logging.Verbose;
		    $PSDefaultParameterValues['*:Debug'] = $Global:Logging.Debug;
		    $Global:ErrorActionPreference = 'Stop';
		}
		function Invoke-Teardown {
		    $PSDefaultParameterValues.Remove('*:ErrorAction');
		    $PSDefaultParameterValues.Remove('*:WarningAction');
		    $PSDefaultParameterValues.Remove('*:InformationAction');
		    $PSDefaultParameterValues.Remove('*:Verbose');
		    $PSDefaultParameterValues.Remove('*:Debug');
		}
		function Import-CommonModules {
		    [HashTable]$Local:ToImport = [Ordered]@{};
		    function Get-FilsAsHashTable([String]$Path) {
		        [HashTable]$Local:HashTable = [Ordered]@{};
		        Get-ChildItem -File -Path "$($MyInvocation.MyCommand.Module.Path | Split-Path -Parent)/*.psm1" | ForEach-Object {
		            [System.IO.FileInfo]$Local:File = $_;
		            $Local:HashTable[$Local:File.BaseName] = $Local:File.FullName;
		        };
		        return $Local:HashTable;
		    }
		    function Import-ModuleOrScriptBlock([String]$Name, [Object]$Value) {
		        begin {
		            $Local:Hasher = [System.Security.Cryptography.SHA256]::Create();
		        }
		        process {
		            Invoke-EnvDebug -Message "Importing module $Name.";
		            if ($Value -is [ScriptBlock]) {
		                Invoke-EnvDebug -Message "Module $Name is a script block.";
		                $Local:ContentHash = ($Local:Hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes(($Value -as [ScriptBlock]).Ast.Extent.Text)) | ForEach-Object { $_.ToString('x2') }) -join '';
		                $Local:ModuleName = "$Name-$Local:ContentHash.psm1";
		                $Local:ModulePath = ($env:TEMP | Join-Path -ChildPath "$Local:ModuleName");
		                if (-not (Test-Path $Private:ModulePath)) {
		                    Set-Content -Path $Private:ModulePath -Value $Value.ToString();
		                }
		                Import-Module -Name $Private:ModulePath -Global -Force -Verbose:$False -Debug:$False;
		            }
		            else {
		                Invoke-EnvDebug -Message "Module $Name is a file or installed module.";
		                Import-Module -Name $Value -Global -Force -Verbose:$False -Debug:$False;
		            }
		        }
		    }
		    if (Test-IsCompiledScript) {
		        Invoke-EnvVerbose 'Script has been embeded with required modules.';
		        [HashTable]$Local:ToImport = $Global:EmbededModules;
		    }
		    elseif (Test-Path -Path "$($MyInvocation.MyCommand.Module.Path | Split-Path -Parent)/../../.git") {
		        Invoke-EnvVerbose 'Script is in git repository; Using local files.';
		        [HashTable]$Local:ToImport = Get-FilsAsHashTable -Path "$($MyInvocation.MyCommand.Module.Path | Split-Path -Parent)/*.psm1";
		    }
		    else {
		        [String]$Local:RepoPath = "$($env:TEMP)/AMTScripts";
		        if (Get-Command -Name 'git' -ErrorAction SilentlyContinue) {
		            if (-not (Test-Path -Path $Local:RepoPath)) {
		                Invoke-EnvVerbose -UnicodePrefix '♻️' -Message 'Cloning repository.';
		                git clone https://github.com/AMTSupport/scripts.git $Local:RepoPath;
		            }
		            else {
		                Invoke-EnvVerbose -UnicodePrefix '♻️' -Message 'Updating repository.';
		                git -C $Local:RepoPath pull;
		            }
		        }
		        else {
		            Invoke-EnvInfo -Message 'Git is not installed, unable to update the repository or clone if required.';
		        }
		        [HashTable]$Local:ToImport = Get-FilsAsHashTable -Path "$Local:RepoPath/src/common/*.psm1";
		    }
		    Import-ModuleOrScriptBlock -Name:'00-PSStyle' -Value:$Local:ToImport['00-PSStyle'];
		    Invoke-EnvVerbose -Message "Importing $($Local:ToImport.Count) modules.";
		    Invoke-EnvVerbose -Message "Modules to import: `n$(($Local:ToImport.Keys | Sort-Object) -join "`n")";
		    foreach ($Local:ModuleName in $Local:ToImport.Keys | Sort-Object) {
		        $Local:ModuleName = $Local:ModuleName;
		        $Local:ModuleValue = $Local:ToImport[$Local:ModuleName];
		        if ($Local:ModuleName -eq '00-Environment') {
		            continue;
		        }
		        if ($Local:ModuleName -eq '00-PSStyle') {
		            continue;
		        }
		        Import-ModuleOrScriptBlock -Name $Local:ModuleName -Value $Local:ModuleValue;
		        if ($Local:ModuleName -eq '01-Logging') {
		            $Global:Logging.Loaded = $true;
		        }
		    }
		    $Script:ImportedModules += $Local:ToImport.Keys;
		}
		function Remove-CommonModules {
		    Invoke-EnvVerbose -Message "Cleaning up $($Script:ImportedModules.Count) imported modules.";
		    Invoke-EnvVerbose -Message "Removing modules: `n$(($Script:ImportedModules | Sort-Object -Descending) -join "`n")";
		    $Script:ImportedModules | Sort-Object -Descending | ForEach-Object {
		        $Private:Module = $_;
		        Invoke-EnvDebug -Message "Removing module $Private:Module.";
		        if ($Local:Module -eq '01-Logging') {
		            Invoke-EnvDebug -Message 'Resetting logging state.';
		            $Global:Logging.Loaded = $false;
		        }
		        try {
		            Invoke-EnvDebug -Message "Running Remove-Module -Name $Private:Module";
		            Remove-Module -Name "$Private:Module*" -Force -Verbose:$False -Debug:$False;
		            if (($Private:Module -ne '00-Environment') -and (Test-IsCompiledScript)) {
		                Remove-Item -Path ($env:TEMP | Join-Path -ChildPath "$($Private:Module)*");
		            }
		        }
		        catch {
		            Invoke-EnvDebug -Message "Failed to remove module $Local:Module";
		        }
		    };
		}
		function Invoke-RunMain {
		    Param(
		        [Parameter(Mandatory)]
		        [ValidateNotNull()]
		        [System.Management.Automation.PSCmdlet]$Cmdlet,
		        [Parameter(Mandatory)]
		        [ValidateNotNull()]
		        [ScriptBlock]$Main,
		        [Parameter(DontShow)]
		        [Switch]$NotStrict = $False,
		        [Parameter(DontShow)]
		        [Switch]$DontImport = (-not (Test-ExplicitlyCalled -Invocation:$Cmdlet.MyInvocation)),
		        [Parameter(DontShow)]
		        [Switch]$HideDisclaimer = ($DontImport -or (Test-IsNableRunner))
		    )
		    function Invoke-Inner {
		        Param(
		            [Parameter(Mandatory)]
		            [ValidateNotNull()]
		            [System.Management.Automation.PSCmdlet]$Cmdlet,
		            [Parameter(Mandatory)]
		            [ValidateNotNull()]
		            [ScriptBlock]$Main,
		            [Parameter(DontShow)]
		            [Switch]$DontImport,
		            [Parameter(DontShow)]
		            [Switch]$HideDisclaimer
		        )
		        begin {
		            if (-not $Global:ScriptRestarted) {
		                foreach ($Local:Param in @('Verbose', 'Debug')) {
		                    if ($Cmdlet.MyInvocation.BoundParameters.ContainsKey($Local:Param)) {
		                        $Global:Logging[$Local:Param] = $Cmdlet.MyInvocation.BoundParameters[$Local:Param];
		                    }
		                }
		                if (-not $HideDisclaimer) {
		                    Invoke-EnvInfo -UnicodePrefix '⚠️' -Message 'Disclaimer: This script is provided as is, without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and non-infringement. In no event shall the author or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the script or the use or other dealings in the script.';
		                }
		                if ($Local:DontImport) {
		                    Invoke-EnvVerbose -UnicodePrefix '♻️' -Message 'Skipping module import.';
		                    return;
		                }
		                Import-CommonModules;
		                Invoke-Setup;
		            }
		        }
		        process {
		            try {
		                if (Test-ExplicitlyCalled -Invocation:$Cmdlet.MyInvocation) {
		                    Invoke-EnvVerbose -UnicodePrefix '🚀' -Message 'Running main function.';
		                    $Local:RunBoundParameters = $Cmdlet.MyInvocation.BoundParameters;
		                    $Cmdlet.InvokeCommand.InvokeScript(
		                        $Cmdlet.SessionState,
		                        $Main,
		                        [System.Management.Automation.Runspaces.PipelineResultTypes]::All,
		                        $Local:RunBoundParameters
		                    );
		                }
		            }
		            catch {
		                $Local:CatchingError = $_;
		                switch ($Local:CatchingError.FullyQualifiedErrorId) {
		                    'QuickExit' {
		                        Invoke-EnvVerbose -UnicodePrefix '✅' -Message 'Main function finished successfully.';
		                    }
		                    'FailedExit' {
		                        [Int]$Local:ExitCode = $Local:CatchingError.TargetObject;
		                        Invoke-EnvVerbose -Message "Script exited with an error code of $Local:ExitCode.";
		                        $LASTEXITCODE = $Local:ExitCode;
		                        $Global:Error.Remove($Local:CatchingError);
		                    }
		                    'RestartScript' {
		                        $Global:ScriptRestarting = $True;
		                    }
		                    default {
		                        Invoke-Error 'Uncaught Exception during script execution';
		                        Invoke-FailedExit -ExitCode 9999 -ErrorRecord $Local:CatchingError -DontExit;
		                    }
		                }
		            }
		            finally {
		                [Boolean]$Private:WasCompiled = Test-IsCompiledScript;
		                [Boolean]$Private:WasRestarted = Test-IsRestartedScript;
		                [Boolean]$Private:IsRestarting = Test-IsRestartingScript;
		                if (-not $Local:DontImport) {
		                    Invoke-Handlers;
		                    Invoke-Teardown;
		                    if (-not (Test-IsRestartingScript)) {
		                        Remove-CommonModules;
		                        if ($Private:WasCompiled) {
		                            Remove-Variable -Scope Global -Name CompiledScript, EmbededModules;
		                        }
		                        Remove-Variable -Scope Global -Name Logging;
		                        if ($Private:WasRestarted) {
		                            Remove-Variable -Scope Global -Name ScriptRestarted;
		                        }
		                    }
		                }
		                if ($Private:IsRestarting) {
		                    Invoke-EnvVerbose -UnicodePrefix '🔄' -Message 'Restarting script.';
		                    Remove-Variable -Scope Global -Name ScriptRestarting;
		                    Set-Variable -Scope Global -Name ScriptRestarted -Value $True; # Bread trail for the script to know it's been restarted.
		                    Invoke-Inner @PSBoundParameters;
		                }
		            }
		        }
		    }
		    if (-not $NotStrict) {
		        Set-StrictMode -Version 3;
		    }
		    Invoke-Inner `
		        -Cmdlet $Cmdlet `
		        -Main $Main `
		        -DontImport:$DontImport `
		        -HideDisclaimer:($HideDisclaimer -or $False) `
		        -Verbose:(Get-OrFalse $Invocation.BoundParameters 'Verbose') `
		        -Debug:(Get-OrFalse $Invocation.BoundParameters 'Debug');
		}
		Export-ModuleMember -Function Invoke-RunMain, Import-CommonModules, Remove-CommonModules, Test-IsNableRunner;
    };`
	"00-PSStyle" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
		$Script:Below7_2 = $PSVersionTable.PSVersion.Major -lt 7 -or $PSVersionTable.PSVersion.Minor -lt 2;
		$ESC = [char]0x1b
		enum OutputRendering {
		    Host
		    PlainText
		    Ansi
		}
		enum ProgressView {
		    Minimal
		    Classic
		}
		class ForegroundColor {
		    [string]$Black = "${ESC}[30m"
		    [string]$BrightBlack = "${ESC}[90m"
		    [string]$White = "${ESC}[37m"
		    [string]$BrightWhite = "${ESC}[97m"
		    [string]$Red = "${ESC}[31m"
		    [string]$BrightRed = "${ESC}[91m"
		    [string]$Magenta = "${ESC}[35m"
		    [string]$BrightMagenta = "${ESC}[95m"
		    [string]$Blue = "${ESC}[34m"
		    [string]$BrightBlue = "${ESC}[94m"
		    [string]$Cyan = "${ESC}[36m"
		    [string]$BrightCyan = "${ESC}[96m"
		    [string]$Green = "${ESC}[32m"
		    [string]$BrightGreen = "${ESC}[92m"
		    [string]$Yellow = "${ESC}[33m"
		    [string]$BrightYellow = "${ESC}[93m"
		    [string]FromRGB ([byte]$r, [byte]$g, [byte]$b) {
		        $ESC = [char]0x1b
		        return "${ESC}[38;2;${r};${g};${b}m"
		    }
		    [string]FromRGB ([uint32]$rgb) {
		        $ESC = [char]0x1b
		        [byte]$r = ($rgb -band 0x00ff0000) -shr 16
		        [byte]$g = ($rgb -band 0x0000ff00) -shr 8
		        [byte]$b = ($rgb -band 0x000000ff)
		        return "${ESC}[38;2;${r};${g};${b}m"
		    }
		}
		class BackgroundColor {
		    [string]$Black = "${ESC}[40m"
		    [string]$BrightBlack = "${ESC}[100m"
		    [string]$White = "${ESC}[47m"
		    [string]$BrightWhite = "${ESC}[107m"
		    [string]$Red = "${ESC}[41m"
		    [string]$BrightRed = "${ESC}[101m"
		    [string]$Magenta = "${ESC}[45m"
		    [string]$BrightMagenta = "${ESC}[105m"
		    [string]$Blue = "${ESC}[44m"
		    [string]$BrightBlue = "${ESC}[104m"
		    [string]$Cyan = "${ESC}[46m"
		    [string]$BrightCyan = "${ESC}[106m"
		    [string]$Green = "${ESC}[42m"
		    [string]$BrightGreen = "${ESC}[102m"
		    [string]$Yellow = "${ESC}[43m"
		    [string]$BrightYellow = "${ESC}[103m"
		    [string]FromRGB ([byte]$r, [byte]$g, [byte]$b) {
		        $ESC = [char]0x1b
		        return "${ESC}[48;2;${r};${g};${b}m"
		    }
		    [string]FromRGB ([uint32]$rgb) {
		        $ESC = [char]0x1b
		        [byte]$r = ($rgb -band 0x00ff0000) -shr 16
		        [byte]$g = ($rgb -band 0x0000ff00) -shr 8
		        [byte]$b = ($rgb -band 0x000000ff)
		        return "${ESC}[48;2;${r};${g};${b}m"
		    }
		}
		class FormattingData {
		    [string]$FormatAccent = "${ESC}[32;1m"
		    [string]$ErrorAccent = "${ESC}[36;1m"
		    [string]$Error = "${ESC}[31;1m"
		    [string]$Warning = "${ESC}[33;1m"
		    [string]$Verbose = "${ESC}[33;1m"
		    [string]$Debug = "${ESC}[33;1m"
		    [string]$TableHeader = "${ESC}[32;1m"
		    [string]$CustomTableHeaderLabel = "${ESC}[32;1;3m"
		    [string]$FeedbackProvider = "${ESC}[33m"
		    [string]$FeedbackText = "${ESC}[96m"
		}
		class ProgressConfiguration {
		    [string]$Style = "${ESC}[33;1m"
		    [int]$MaxWidth = 120
		    [ProgressView ]$View = [ProgressView]::Minimal
		    [bool]$UseOSCIndicator = $false
		}
		class FileInfoFormatting {
		    [string]$Directory = "${ESC}[44;1m"
		    [string]$SymbolicLink = "${ESC}[36;1m"
		    [string]$Executable = "${ESC}[32;1m"
		    [hashtable[]]$Extension = @(
		        @{'.zip' = "${ESC}[31;1m" },
		        @{'.tgz' = "${ESC}[31;1m" },
		        @{'.gz' = "${ESC}[31;1m" },
		        @{'.tar' = "${ESC}[31;1m" },
		        @{'.nupkg' = "${ESC}[31;1m" },
		        @{'.cab' = "${ESC}[31;1m" },
		        @{'.7z' = "${ESC}[31;1m" },
		        @{'.ps1' = "${ESC}[33;1m" },
		        @{'.psd1' = "${ESC}[33;1m" },
		        @{'.psm1' = "${ESC}[33;1m" },
		        @{'.ps1xml' = "${ESC}[33;1m" }
		    )
		}
		class PSStyle {
		    [string]$Reset = "${ESC}[0m"
		    [string]$BlinkOff = "${ESC}[25m"
		    [string]$Blink = "${ESC}[5m"
		    [string]$BoldOff = "${ESC}[22m"
		    [string]$Bold = "${ESC}[1m"
		    [string]$DimOff = "${ESC}[22m"
		    [string]$Dim = "${ESC}[2m"
		    [string]$Hidden = "${ESC}[8m"
		    [string]$HiddenOff = "${ESC}[28m"
		    [string]$Reverse = "${ESC}[7m"
		    [string]$ReverseOff = "${ESC}[27m"
		    [string]$ItalicOff = "${ESC}[23m"
		    [string]$Italic = "${ESC}[3m"
		    [string]$UnderlineOff = "${ESC}[24m"
		    [string]$Underline = "${ESC}[4m"
		    [string]$StrikethroughOff = "${ESC}[29m"
		    [string]$Strikethrough = "${ESC}[9m"
		    [OutputRendering]$OutputRendering = [OutputRendering]::Host
		    [FormattingData]$Formatting = [FormattingData]::new()
		    [ProgressConfiguration]$Progress = [ProgressConfiguration]::new()
		    [FileInfoFormatting]$FileInfo = [FileInfoFormatting]::new()
		    [ForegroundColor]$Foreground = [ForegroundColor]::new()
		    [BackgroundColor]$Background = [BackgroundColor]::new()
		    [string]FormatHyperlink([string]$text, [Uri]$link) {
		        $ESC = [char]0x1b
		        return "${ESC}]8;;${link}${ESC}\${text}${ESC}]8;;${ESC}\"
		    }
		    hidden static [string[]]$BackgroundColorMap = @(
		        "${ESC}[40m", # Black
		        "${ESC}[44m", # DarkBlue
		        "${ESC}[42m", # DarkGreen
		        "${ESC}[46m", # DarkCyan
		        "${ESC}[41m", # DarkRed
		        "${ESC}[45m", # DarkMagenta
		        "${ESC}[43m", # DarkYellow
		        "${ESC}[47m", # Gray
		        "${ESC}[100m", # DarkGray
		        "${ESC}[104m", # Blue
		        "${ESC}[102m", # Green
		        "${ESC}[106m", # Cyan
		        "${ESC}[101m", # Red
		        "${ESC}[105m", # Magenta
		        "${ESC}[103m", # Yellow
		        "${ESC}[107m"  # White
		    )
		    hidden static [string[]]$ForegroundColorMap = @(
		        "${ESC}[30m", # Black
		        "${ESC}[34m", # DarkBlue
		        "${ESC}[32m", # DarkGreen
		        "${ESC}[36m", # DarkCyan
		        "${ESC}[31m", # DarkRed
		        "${ESC}[35m", # DarkMagenta
		        "${ESC}[33m", # DarkYellow
		        "${ESC}[37m", # Gray
		        "${ESC}[90m", # DarkGray
		        "${ESC}[94m", # Blue
		        "${ESC}[92m", # Green
		        "${ESC}[96m", # Cyan
		        "${ESC}[91m", # Red
		        "${ESC}[95m", # Magenta
		        "${ESC}[93m", # Yellow
		        "${ESC}[97m"  # White
		    )
		    hidden static [string] MapColorToEscapeSequence ([ConsoleColor]$color, [bool]$isBackground) {
		        $index = [int]$color
		        if ($index -lt 0 -or $index -ge [PSStyle]::ForegroundColorMap.Length) {
		            throw "Error: Color ($color) out of range."
		        }
		        if ($isBackground) {
		            return [PSStyle]::BackgroundColorMap[$index]
		        } else {
		            return [PSStyle]::ForegroundColorMap[$index]
		        }
		    }
		    static [string] MapForegroundColorToEscapeSequence([ConsoleColor]$foregroundColor) {
		        return [PSStyle]::MapColorToEscapeSequence($foregroundColor, $false)
		    }
		    static [string] MapBackgroundColorToEscapeSequence([ConsoleColor]$backgroundColor) {
		        return [PSStyle]::MapColorToEscapeSequence($backgroundColor, $false)
		    }
		    static [string] MapColorPairToEscapeSequence([ConsoleColor]$foregroundColor, [ConsoleColor]$backgroundColor) {
		        $foreIndex = [int]$foregroundColor
		        $backIndex = [int]$backgroundColor
		        if ($foreIndex -lt 0 -or $foreIndex -ge [PSStyle]::ForegroundColorMap.Length) {
		            throw "Error: ForegroundColor ($foregroundColor) out of range."
		        }
		        if ($backIndex -lt 0 -or $backIndex -ge [PSStyle]::ForegroundColorMap.Length) {
		            throw "Error: BackgroundColor ($backgroundColor) out of range."
		        }
		        $fgColor = [PSStyle]::ForegroundColorMap[$foreIndex];
		        $bgColor = [PSStyle]::BackgroundColorMap[$backIndex];
		        return "${fgColor};${bgColor}"
		    }
		}
		function Get-ConsoleColour([Parameter(Mandatory)][System.ConsoleColor]$Colour) {
		    if ($Below7_2) {
		        [PSStyle]::MapForegroundColorToEscapeSequence($Colour)
		    } else {
		        $PSStyle.Foreground.FromConsoleColor($Colour)
		    }
		}
		if ($PSVersionTable.PSVersion.Major -lt 7 -or $PSVersionTable.PSVersion.Minor -lt 2) {
		    $PSStyle = [PSStyle]::new()
		    Export-ModuleMember -Variable PSStyle -Function Get-ConsoleColour;
		} else {
		    Export-ModuleMember -Function Get-ConsoleColour;
		}
    };`
	"00-Utils" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
		function Measure-ElaspedTime {
		    param(
		        [Parameter(Mandatory, ValueFromPipeline)]
		        [ScriptBlock]$ScriptBlock
		    )
		    process {
		        [DateTime]$Local:StartAt = Get-Date;
		        & $ScriptBlock;
		        [TimeSpan]$Local:ElapsedTime = (Get-Date) - $Local:StartAt;
		        return $Local:ElapsedTime * 10000; # Why does this make it more accurate?
		    }
		}
		function Get-VarOrSave {
		    param (
		        [Parameter(Mandatory)]
		        [ValidateNotNullorEmpty()]
		        [String]$VariableName,
		        [Parameter(Mandatory)]
		        [ScriptBlock]$LazyValue,
		        [Parameter()]
		        [ScriptBlock]$Validate
		    )
		    begin { Enter-Scope; }
		    end { Exit-Scope -ReturnValue $Local:Value; }
		    process {
		        $Local:EnvValue = [Environment]::GetEnvironmentVariable($VariableName);
		        if ($Local:EnvValue) {
		            if ($Validate) {
		                try {
		                    if ($Validate.InvokeReturnAsIs($Local:EnvValue)) {
		                        Invoke-Debug "Validated environment variable ${VariableName}: $Local:EnvValue";
		                        return $Local:EnvValue;
		                    }
		                    else {
		                        Invoke-Error "Failed to validate environment variable ${VariableName}: $Local:EnvValue";
		                        [Environment]::SetEnvironmentVariable($VariableName, $null, 'Process');
		                    };
		                }
		                catch {
		                    Invoke-Error "
		                    Failed to validate environment variable ${VariableName}: $Local:EnvValue.
		                    Due to reason ${$_.Exception.Message}".Trim();
		                    [Environment]::SetEnvironmentVariable($VariableName, $null, 'Process');
		                }
		            }
		            else {
		                Invoke-Debug "Found environment variable $VariableName with value $Local:EnvValue";
		                return $Local:EnvValue;
		            }
		        }
		        while ($True) {
		            try {
		                $Local:Value = $LazyValue.InvokeReturnAsIs();
		                if ($Validate) {
		                    if ($Validate.InvokeReturnAsIs($Local:Value)) {
		                        Invoke-Debug "Validated lazy value for environment variable ${VariableName}: $Local:Value";
		                        break;
		                    }
		                    else {
		                        Invoke-Error "Failed to validate lazy value for environment variable ${VariableName}: $Local:Value";
		                    }
		                }
		                else {
		                    break;
		                }
		            }
		            catch {
		                Invoke-Error "Encountered an error while evalutating LazyValue for ${VariableName}.";
		                return $null;
		            }
		        };
		        [Environment]::SetEnvironmentVariable($VariableName, $Local:Value, 'Process');
		        return $Local:Value;
		    }
		}
		function Get-Ast {
		    [CmdletBinding()]
		    param(
		        [Parameter(Mandatory, HelpMessage = 'The input object to transform into an AST object.')]
		        [ValidateNotNullOrEmpty()]
		        [Object]$InputObject
		    )
		    process {
		        $Local:Ast = switch ($InputObject) {
		            { $_ -is [String] } {
		                if (Test-Path -LiteralPath $_) {
		                    $Local:Path = Resolve-Path -Path $_;
		                    [System.Management.Automation.Language.Parser]::ParseFile($Local:Path.ProviderPath, [ref]$null, [ref]$null)
		                }
		                else {
		                    [System.Management.Automation.Language.Parser]::ParseInput($_, [ref]$null, [ref]$null)
		                }
		                break
		            }
		            { $_ -is [System.Management.Automation.FunctionInfo] -or $_ -is [System.Management.Automation.ExternalScriptInfo] } {
		                $InputObject.ScriptBlock.Ast
		                break
		            }
		            { $_ -is [ScriptBlock] } {
		                $_.Ast
		                break
		            }
		            { $_ -is [System.Management.Automation.Language.Ast] } {
		                $_
		                break
		            } Default {
		                Invoke-Warn -Message "InputObject type not recognised: $($InputObject.gettype())";
		                $null
		            }
		        }
		        return $Local:Ast;
		    }
		}
		function Get-ReturnType {
		    [CmdletBinding()]
		    param(
		        [Parameter(Mandatory, HelpMessage = 'The AST object to test.')]
		        [ValidateNotNullOrEmpty()]
		        [Object]$InputObject
		    )
		    process {
		        $Local:Ast = Get-Ast -InputObject $InputObject;
		        $Local:AllReturnStatements = $Local:Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ReturnStatementAst] }, $true);
		        if ($Local:AllReturnStatements.Count -eq 0) {
		            Invoke-Debug -Message 'No return statements found in the AST Object.';
		            return $null;
		        }
		        [System.Reflection.TypeInfo[]]$Local:ReturnTypes = @();
		        foreach ($Local:ReturnStatement in $Local:AllReturnStatements) {
		            if ($Local:ReturnStatement.Pipeline.PipelineElements.Count -eq 0) {
		                Invoke-Debug -Message 'No pipeline elements found in the return statement.';
		                return $null;
		            }
		            [System.Management.Automation.Language.ExpressionAst]$Local:Expression = $Local:ReturnStatement.Pipeline.PipelineElements[0].expression;
		            if ($Local:Expression.VariablePath) {
		                [String]$Local:VariableName = $Local:Expression.VariablePath.UserPath;
		                if ($Local:VariableName -eq 'null') {
		                    $Local:ReturnTypes += [Void];
		                    continue;
		                }
		                $Local:Variable = Get-Variable -Name:$Local:VariableName -ValueOnly -ErrorAction SilentlyContinue;
		                if ($Local:Variable) {
		                    [System.Reflection.TypeInfo]$Local:ReturnType = $Local:Variable.GetType();
		                    $Local:ReturnTypes += $Local:ReturnType;
		                }
		                else {
		                    Invoke-Warn -Message "Could not resolve the variable: $Local:VariableName.";
		                    continue
		                }
		            }
		            else {
		                [System.Reflection.TypeInfo]$Local:ReturnType = $Local:Expression.StaticType;
		                $Local:ReturnTypes += $Local:ReturnType;
		            }
		        }
		        return $Local:ReturnTypes | Sort-Object -Unique;
		    }
		}
		function Test-ReturnType {
		    [CmdletBinding()]
		    param(
		        [Parameter(Mandatory, HelpMessage = 'The AST object to test.')]
		        [ValidateNotNullOrEmpty()]
		        [Object]$InputObject,
		        [Parameter(Mandatory, HelpMessage = 'The Valid Types to test against.')]
		        [ValidateNotNullOrEmpty()]
		        [System.Reflection.TypeInfo[]]$ValidTypes,
		        [Parameter(HelpMessage = 'Allow the return type to be null.')]
		        [Switch]$AllowNull
		    )
		    process {
		        $Local:Ast = Get-Ast -InputObject $InputObject;
		        $Local:ReturnTypes = Get-ReturnType -InputObject $InputObject;
		        if ($null -eq $Local:ReturnTypes) {
		            Invoke-Debug -Message 'No return types found in the AST Object.';
		            return $False;
		        }
		        foreach ($Local:ReturnType in $Local:ReturnTypes) {
		            if ($ValidTypes -contains $Local:ReturnType) {
		                continue;
		            }
		            elseif ($AllowNull -and $Local:ReturnType -eq [Void]) {
		                continue;
		            }
		            else {
		                Invoke-Warn -Message "The return type of the AST object is not valid. Expected: $($ValidTypes -join ', '); Actual: $($Local:ReturnType.Name)";
		                return $False;
		            }
		        }
		        return $True;
		        $Local:AllReturnStatements = $Local:Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ReturnStatementAst] }, $true);
		        if ($Local:AllReturnStatements.Count -eq 0) {
		            Invoke-Debug -Message 'No return statements found in the script block.';
		            return $False;
		        }
		        foreach ($Local:ReturnStatement in $Local:AllReturnStatements) {
		            if ($Local:ReturnStatement.Pipeline.PipelineElements.Count -eq 0) {
		                Invoke-Debug -Message 'No pipeline elements found in the return statement.';
		                return $False;
		            }
		            [System.Management.Automation.Language.ExpressionAst]$Local:Expression = $Local:ReturnStatement.Pipeline.PipelineElements[0].expression;
		            if ($Local:Expression.VariablePath) {
		                [String]$Local:VariableName = $Local:Expression.VariablePath.UserPath;
		                $Local:Variable = Get-Variable -Name:$Local:VariableName -ValueOnly -ErrorAction SilentlyContinue;
		                if ($Local:Variable) {
		                    [System.Reflection.TypeInfo]$Local:ReturnType = $Local:Variable.GetType();
		                    if ($ValidTypes -contains $Local:ReturnType) {
		                        continue;
		                    }
		                }
		                else {
		                    Invoke-Debug -Message "Could not resolve the variable: $Local:VariableName.";
		                    continue
		                }
		            }
		            else {
		                [System.Reflection.TypeInfo]$Local:ReturnType = $Local:Expression.StaticType;
		                [String]$Local:TypeName = $Local:ReturnType.Name;
		                Invoke-Debug "Return type: $Local:TypeName";
		                if ($ValidTypes -contains $Local:TypeName -or ($AllowNull -and $Local:Expression.Extent.Text -eq '$null' -and $Local:ReturnType.Name -eq 'Object')) {
		                    continue;
		                }
		            }
		            $Local:Region = $Local:Expression.Extent;
		            Invoke-Warn -Message @"
The return type of the script block is not valid. Expected: $($ValidTypes -join ', '); Actual: $Local:TypeName.
At: $($Local:Region.StartLineNumber):$($Local:Region.StartColumnNumber) - $($Local:Region.EndLineNumber):$($Local:Region.EndColumnNumber)
Text: $($Local:Region.Text)
"@;
		            return $False;
		        }
		        return $True;
		    }
		}
		function Test-Parameters {
		    [CmdletBinding()]
		    param(
		        [Parameter(Mandatory, HelpMessage = 'The AST object to test.')]
		        [ValidateNotNullOrEmpty()]
		        [Object]$InputObject,
		        [Parameter(Mandatory, HelpMessage = 'The Valid Types to test against.')]
		        [ValidateNotNullOrEmpty()]
		        [String[]]$ValidTypes
		    )
		    process {
		        $Local:Ast = Get-Ast -InputObject $InputObject;
		        $Local:AllParamStatements = $Local:Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ParameterAst] }, $true);
		        foreach ($Local:ParamStatement in $Local:AllParamStatements) {
		            [System.Management.Automation.Language.ParameterAst]$Local:Param = $Local:ParamStatement;
		            [String]$Local:TypeName = $Local:Param.StaticType.Name;
		            if ($ValidTypes -contains $Local:TypeName) {
		                continue;
		            }
		            Invoke-Warn -Message "The parameter type of the script block is not valid. Expected: $($ValidTypes -join ', '); Actual: $Local:TypeName";
		            return $False;
		        }
		        return $True;
		    }
		}
		function Install-ModuleFromGitHub {
		    [CmdletBinding()]
		    param(
		        [Parameter(Mandatory)]
		        [String]$GitHubRepo,
		        [Parameter(Mandatory)]
		        [String]$Branch,
		        [ValidateSet('CurrentUser', 'AllUsers')]
		        [String]$Scope = 'CurrentUser'
		    )
		    process {
		        Invoke-Verbose ("[$(Get-Date)] Retrieving {0} {1}" -f $GitHubRepo, $Branch);
		        [String]$Local:ZipballUrl = "https://api.github.com/repos/$GithubRepo/zipball/$Branch";
		        [String]$Local:ModuleName = $GitHubRepo.split('/')[-1]
		        [String]$Local:TempDir = [System.IO.Path]::GetTempPath();
		        [String]$Local:OutFile = Join-Path -Path $Local:TempDir -ChildPath "$($ModuleName).zip";
		        if (-not ($IsLinux -or $IsMacOS)) {
		            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;
		        }
		        Invoke-Verbose "Downloading $Local:ModuleName from $Local:ZipballUrl to $Local:OutFile";
		        try {
		            $ErrorActionPreference = 'Stop';
		            Invoke-RestMethod $Local:ZipballUrl -OutFile $Local:OutFile;
		        }
		        catch {
		            Invoke-Error "Failed to download $Local:ModuleName from $Local:ZipballUrl to $Local:OutFile";
		            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
		        }
		        if (-not ([System.Environment]::OSVersion.Platform -eq 'Unix')) {
		            Unblock-File $Local:OutFile;
		        }
		        [String]$Local:FileHash = (Get-FileHash -Path $Local:OutFile).hash;
		        [String]$Local:ExtractDir = Join-Path -Path $Local:TempDir -ChildPath $Local:FileHash;
		        Invoke-Verbose "Extracting $Local:OutFile to $Local:ExtractDir";
		        try {
		            Expand-Archive -Path $Local:OutFile -DestinationPath $Local:ExtractDir -Force;
		        }
		        catch {
		            Invoke-Error "Failed to extract $Local:OutFile to $Local:ExtractDir";
		            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
		        }
		        [System.IO.DirectoryInfo]$Local:UnzippedArchive = Get-ChildItem -Path $Local:ExtractDir -Directory | Select-Object -First 1;
		        switch ($Scope) {
		            'CurrentUser' {
		                [String]$Local:PSModulePath = ($PSGetPath).CurrentUserModules;
		                break;
		            }
		            'AllUsers' {
		                [String]$Local:PSModulePath = ($PSGetPath).AllUsersModules;
		                break;
		            }
		        }
		        if ([System.Environment]::OSVersion.Platform -eq 'Unix') {
		            [System.IO.FileInfo[]]$Local:ManifestFiles = Get-ChildItem (Join-Path -Path $Local:UnzippedArchive -ChildPath *) -File | Where-Object { $_.Name -like '*.psd1' };
		        }
		        else {
		            [System.IO.FileInfo[]]$Local:ManifestFiles = Get-ChildItem -Path $Local:UnzippedArchive.FullName -File | Where-Object { $_.Name -like '*.psd1' };
		        }
		        if ($Local:ManifestFiles.Count -eq 0) {
		            Invoke-Error "No manifest file found in $($Local:UnzippedArchive.FullName)";
		            Invoke-FailedExit -ExitCode 9999;
		        }
		        elseif ($Local:ManifestFiles.Count -gt 1) {
		            Invoke-Debug "Multiple manifest files found in $($Local:UnzippedArchive.FullName)";
		            Invoke-Debug "Manifest files: $($Local:ManifestFiles.FullName -join ', ')";
		            [System.IO.FileInfo]$Local:ManifestFile = $Local:ManifestFiles | Where-Object { $_.Name -like "$Local:ModuleName*.psd1" } | Select-Object -First 1;
		        }
		        else {
		            [System.IO.FileInfo]$Local:ManifestFile = $Local:ManifestFiles | Select-Object -First 1;
		            Invoke-Debug "Manifest file: $($Local:ManifestFile.FullName)";
		        }
		        $Local:Manifest = Test-ModuleManifest -Path $Local:ManifestFile.FullName;
		        [String]$Local:ModuleName = $Local:Manifest.Name;
		        [String]$Local:ModuleVersion = $Local:Manifest.Version;
		        [String]$Local:SourcePath = $Local:ManifestFile.DirectoryName;
		        [String]$Local:TargetPath = (Join-Path -Path $Local:PSModulePath -ChildPath (Join-Path -Path $Local:ModuleName -ChildPath $Local:ModuleVersion));
		        New-Item -ItemType directory -Path $Local:TargetPath -Force | Out-Null;
		        Invoke-Debug "Copying $Local:SourcePath to $Local:TargetPath";
		        if ([System.Environment]::OSVersion.Platform -eq 'Unix') {
		            Copy-Item "$(Join-Path -Path $Local:UnzippedArchive -ChildPath *)" $Local:TargetPath -Force -Recurse | Out-Null;
		        }
		        else {
		            Copy-Item "$Local:SourcePath\*" $Local:TargetPath -Force -Recurse | Out-Null;
		        }
		        return $Local:ModuleName;
		    }
		}
		function Test-NetworkConnection {
		    (Get-NetConnectionProfile | Where-Object {
		        $Local:HasIPv4 = $_.IPv4Connectivity -eq 'Internet';
		        $Local:HasIPv6 = $_.IPv6Connectivity -eq 'Internet';
		        $Local:HasIPv4 -or $Local:HasIPv6
		    } | Measure-Object | Select-Object -ExpandProperty Count) -gt 0;
		}
		function Export-Types {
		    [CmdletBinding()]
		    param(
		        [Parameter(Mandatory)]
		        [Type[]]$Types,
		        [Switch]$Clobber,
		        [Parameter(DontShow)]
		        [PSModuleInfo]$Module = (Get-PSCallStack)[0].InvocationInfo.MyCommand.ScriptBlock.Module
		    )
		    if (-not $Module) {
		        throw [System.InvalidOperationException]::new('This function must be called from within a module.');
		    }
		    $TypeAcceleratorsClass = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators');
		    if (-not $Clobber) {
		        $ExistingTypeAccelerators = $TypeAcceleratorsClass::Get;
		        foreach ($Type in $Types) {
		            if ($Type.FullName -in $ExistingTypeAccelerators.Keys) {
		                $Message = @(
		                    "Unable to register type accelerator '$($Type.FullName)'"
		                    'Accelerator already exists.'
		                ) -join ' - '
		                throw [System.Management.Automation.ErrorRecord]::new(
		                    [System.InvalidOperationException]::new($Message),
		                    'TypeAcceleratorAlreadyExists',
		                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
		                    $Type.FullName
		                )
		            }
		        }
		    }
		    foreach ($Type in $Types) {
		        $TypeAcceleratorsClass::Add($Type.FullName, $Type);
		    }
		    Invoke-Debug "Exported types: $($Types -join ', ')";
		    Invoke-Debug "Registering module callback to remove type accelerators: $($Types -join ', ') from $($Module)";
		    Add-ModuleCallback -Module $Module -ScriptBlock {
		        foreach ($Type in $Types) {
		            $null = $TypeAcceleratorsClass::Remove($Type.FullName);
		        }
		    }.GetNewClosure();
		}
		function Add-ModuleCallback {
		    [CmdletBinding()]
		    param(
		        [Parameter(Mandatory)]
		        $ScriptBlock,
		        [Parameter()]
		        $Module = (Get-PSCallStack)[0].InvocationInfo.MyCommand.ScriptBlock.Module
		    )
		    if (-not $Module) {
		        throw [System.InvalidOperationException]::new('This function must be called from within a module.');
		    }
		    $Module.OnRemove = $ScriptBlock;
		}
		function Wait-Task {
		    [CmdletBinding()]
		    [Alias('await')]
		    param(
		        [Parameter(Mandatory, ValueFromPipeline)]
		        [PSCustomObject[]]$Run,
		        [Switch]$PassThru
		    )
		    Begin {
		        $Running = @{};
		        $Finished = { $_.IsCompleted -or ($_.JobStateInfo.State -gt 1 -and $_.JobStateInfo.State -ne 6 -and $_.JobStateInfo.State -ne 8) };
		        $Handle = { $_.AsyncWaitHandle };
		    }
		    Process {
		        if (-not ($Run.Job -and $Run.Job.Id)) {
		            throw [System.InvalidOperationException]::new('The Run object must contain a Job with an Id.');
		        }
		        $Running.Add($Run.Job.Id, $Run) | Out-Null;
		    }
		    End {
		        filter Complete-Job {
		            $Local:Out = $Running.Item($_.Id);
		            $Running.Remove($_.Id) | Out-Null;
		            if (-not ($Local:Out | Get-Member -Name 'Result' -MemberType NoteProperty)) {
		                $Local:Result = if ($_.PWSH) {
		                    try {
		                        $_.PWSH.EndInvoke($_)
		                    }
		                    catch {
		                        $_.Exception.InnerException
		                    }
		                    finally {
		                        $_.PWSH.Dispose()
		                    }
		                }
		                elseif ($_.IsFaulted) {
		                    $_.Exception.InnerException
		                }
		                else {
		                    $_.Result
		                }
		                $Local:Out | Add-Member -MemberType NoteProperty -Name Result -Value $Local:Result;
		            }
		            if ($PassThru) {
		                $Local:Out
		            }
		            else {
		                $Local:Out.Result
		            }
		        }
		        while ($Running.Count -gt 0) {
		            function Get-Jobs {
		                param($Filter)
		                $Running.Values | ForEach-Object { $_.Job } | Where-Object $Filter;
		            }
		            [System.Threading.WaitHandle]::WaitAny((Get-Jobs -Filter $Handle | ForEach-Object $Handle)) | Out-Null;
		            (Get-Jobs -Filter $Finished) | Complete-Job;
		        }
		    }
		}
		function Start-AsyncTask {
		    [CmdletBinding()]
		    [Alias('async')]
		    param(
		        [Parameter(Mandatory)]
		        [ScriptBlock]$ScriptBlock
		    )
		    process {
		        [PSCustomObject]$Local:Run = [PSCustomObject]@{
		            Input = $_;
		            Job   = $null;
		        };
		        [Powershell]$PWSH = [Powershell]::Create();
		        $PWSH.AddScript($ScriptBlock) | Out-Null;
		        if ($null -ne $Local:Run.Input) {
		            $Local:Run.Job = $PWSH.BeginInvoke([System.Management.Automation.PSDataCollection[PSObject]]::new([PSObject[]]($Local:Run.Input)));
		        }
		        else {
		            $Local:Run.Job = $PWSH.BeginInvoke();
		        }
		        $Run.Job | Add-Member -MemberType NoteProperty -Name pwsh -Value $PWSH -PassThru | Add-Member -MemberType NoteProperty -Name Id -Value $Run.Job.AsyncWaitHandle.Handle.ToString();
		        return $Local:Run;
		    }
		}
		function Add-LazyProperty {
		    [CmdletBinding()]
		    param (
		        [Parameter(Mandatory, ValueFromPipeline = $true)]
		        [PSObject]$InputObject,
		        [Parameter(Mandatory, Position = 1)]
		        [String]$Name,
		        [Parameter(Mandatory, Position = 2)]
		        [ScriptBlock]$Value,
		        [Switch]$PassThru
		    )
		    process {
		        $Local:LazyValue = {
		            $Local:Result = & $Value;
		            Add-Member -InputObject $this -MemberType NoteProperty -Name $Name -Value $Local:Result -Force;
		            $Local:Result;
		        }.GetNewClosure();
		        Add-Member -InputObject:$InputObject -MemberType:ScriptProperty -Name:$Name -Value:$Local:LazyValue -PassThru:$Local:PassThru;
		    }
		}
		function Set-LazyVariable {
		    [CmdletBinding()]
		    [Alias('lazy')]
		    param (
		        [Parameter(Mandatory, Position = 1)]
		        [String]$Name,
		        [Parameter(Mandatory, Position = 2)]
		        [ScriptBlock]$Value,
		        [Switch]$PassThru
		    )
		    process {
		        $Local:LazyValue = {
		            $Local:Result = & $Value;
		            Set-Variable -Name $Local:Name -Value $Local:Result -Scope Local -Option ReadOnly;
		            $Local:Result;
		        }.GetNewClosure();
		        Set-Variable -Name:$Name -Value:$Local:LazyValue -Scope:Local -Option:ReadOnly -PassThru:$PassThru;
		    }
		}
		function Test-IsRunningAsSystem {
		    [System.Security.Principal.WindowsIdentity]::GetCurrent().Name -eq 'NT AUTHORITY\SYSTEM';
		}
		Export-ModuleMember -Function * -Alias *;
    };`
	"01-Logging" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
		function Test-SupportsUnicode {
		    $null -ne $env:WT_SESSION -and -not (Test-IsNableRunner);
		}
		function Test-SupportsColour {
		    $Host.UI.SupportsVirtualTerminal -and -not (Test-IsNableRunner);
		}
		function Invoke-Write {
		    [CmdletBinding(PositionalBinding, DefaultParameterSetName = 'Splat')]
		    param (
		        [Parameter(ParameterSetName = 'InputObject', Position = 0, ValueFromPipeline)]
		        [HashTable]$InputObject,
		        [Parameter(ParameterSetName = 'Splat', Mandatory, ValueFromPipelineByPropertyName)]
		        [ValidateNotNullOrEmpty()]
		        [String]$PSMessage,
		        [Parameter(ParameterSetName = 'Splat', ValueFromPipelineByPropertyName, HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
		        [String]$PSPrefix,
		        [Parameter(ParameterSetName = 'Splat', Mandatory, ValueFromPipelineByPropertyName)]
		        [ValidateNotNullOrEmpty()]
		        [String]$PSColour,
		        [Parameter(ParameterSetName = 'Splat', ValueFromPipelineByPropertyName)]
		        [ValidateNotNullOrEmpty()]
		        [Boolean]$ShouldWrite,
		        [Parameter(ParameterSetName = 'Splat', ValueFromPipelineByPropertyName)]
		        [ValidateNotNullOrEmpty()]
		        [Switch]$PassThru
		    )
		    process {
		        if ($InputObject) {
		            Invoke-Write @InputObject;
		            return;
		        }
		        if (-not $ShouldWrite -and -not $PassThru) {
		            return;
		        }
		        [String]$Local:NewLineTab = if ($PSPrefix -and (Test-SupportsUnicode)) {
		            "$(' ' * $($PSPrefix.Length))";
		        } else { ''; }
		        [String]$Local:FormattedMessage = if ($PSMessage.Contains("`n")) {
		            $PSMessage -replace "`n", "`n$Local:NewLineTab+ ";
		        } else { $PSMessage; }
		        if (Test-SupportsColour) {
		            $Local:FormattedMessage = "$(Get-ConsoleColour $PSColour)$Local:FormattedMessage$($PSStyle.Reset)";
		        }
		        [String]$Local:FormattedMessage = if ($PSPrefix -and (Test-SupportsUnicode)) {
		            "$PSPrefix $Local:FormattedMessage";
		        } else { $Local:FormattedMessage; }
		        if ($PassThru) {
		            return $Local:FormattedMessage;
		        } else {
		            $InformationPreference = 'Continue';
		            Write-Information $Local:FormattedMessage;
		        }
		    }
		}
		function Format-Error(
		    [Parameter(Mandatory, HelpMessage = 'The error records invocation info.')]
		    [ValidateNotNullOrEmpty()]
		    [System.Management.Automation.InvocationInfo]$InvocationInfo,
		    [Parameter(HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
		    [ValidateNotNullOrEmpty()]
		    [String]$Message,
		    [Parameter(HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
		    [ValidateNotNullOrEmpty()]
		    [Alias('Prefix')]
		    [String]$UnicodePrefix,
		    [Parameter(HelpMessage = 'Return the formatted message instead of writing it to the console.')]
		    [Switch]$PassThru
		) {
		    [String]$Local:TrimmedLine = $InvocationInfo.Line.Trim();
		    [String]$Local:Script = $InvocationInfo.ScriptName.Trim();
		    if ($InvocationInfo.Statement) {
		        [String]$Local:Statement = $InvocationInfo.Statement.Trim();
		        [Int]$Local:StatementIndex = $Local:TrimmedLine.IndexOf($Local:Statement);
		        if ($Local:StatementIndex -lt 0) {
		            [Int]$Local:StatementIndex = 0;
		        }
		    } else {
		        [Int]$Local:StatementIndex = 0;
		        [String]$Local:Statement = $TrimmedLine;
		    }
		    [String]$Local:Underline = (' ' * ($Local:StatementIndex + 10)) + ('^' * $Local:Statement.Length);
		    [String]$Local:Message = if ($null -ne $Message) {
		        (' ' * $Local:StatementIndex) + $Message;
		    } else { $null };
		    [HashTable]$Private:BaseArgs = @{
		        PSPrefix    = if ($UnicodePrefix) { $UnicodePrefix } else { $null };
		        ShouldWrite = $True;
		        PassThru    = $PassThru;
		    };
		    Invoke-Write @Private:BaseArgs -PSMessage "File    | $($PSStyle.Foreground.Red)$Local:Script" -PSColour Cyan;
		    Invoke-Write @Private:BaseArgs -PSMessage "Line    | $($PSStyle.Foreground.Red)$($InvocationInfo.ScriptLineNumber)" -PSColour Cyan;
		    Invoke-Write @Private:BaseArgs -PSMessage "Preview | $($PSStyle.Foreground.Red)$Local:TrimmedLine" -PSColour Cyan;
		    Invoke-Write @Private:BaseArgs -PSMessage "$Local:Underline" -PSColour 'Red';
		    if ($Local:Message) {
		        Invoke-Write @Private:BaseArgs -PSMessage "Message | $($PSStyle.Foreground.Red)$Local:Message" -PSColour Cyan;
		    }
		}
		function Invoke-Verbose {
		    [CmdletBinding(PositionalBinding, DefaultParameterSetName = 'Splat')]
		    param(
		        [Parameter(ParameterSetName = 'InputObject', Position = 0, ValueFromPipeline)]
		        [HashTable]$InputObject,
		        [Parameter(ParameterSetName = 'Splat', Position = 0, ValueFromPipelineByPropertyName, Mandatory, HelpMessage = 'The message to write to the console.')]
		        [ValidateNotNullOrEmpty()]
		        [String]$Message,
		        [Parameter(ParameterSetName = 'Splat', Position = 1, ValueFromPipelineByPropertyName, HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
		        [ValidateNotNullOrEmpty()]
		        [Alias('Prefix')]
		        [String]$UnicodePrefix,
		        [Parameter(ValueFromPipelineByPropertyName, HelpMessage = 'Return the formatted message instead of writing it to the console.')]
		        [Switch]$PassThru
		    )
		    process {
		        if ($InputObject) {
		            Invoke-Verbose @InputObject;
		            return;
		        }
		        $Local:Params = @{
		            PSPrefix    = if ($UnicodePrefix) { $UnicodePrefix } else { '🔍' };
		            PSMessage   = $Message;
		            PSColour    = 'Yellow';
		            ShouldWrite = $Global:Logging.Verbose;
		            PassThru    = $PassThru;
		        };
		        Invoke-Write @Local:Params;
		    }
		}
		function Invoke-Debug {
		    [CmdletBinding(PositionalBinding, DefaultParameterSetName = 'Splat')]
		    param(
		        [Parameter(ParameterSetName = 'InputObject', Position = 0, ValueFromPipeline)]
		        [HashTable]$InputObject,
		        [Parameter(ParameterSetName = 'Splat', Position = 0, ValueFromPipelineByPropertyName, Mandatory, HelpMessage = 'The message to write to the console.')]
		        [ValidateNotNullOrEmpty()]
		        [String]$Message,
		        [Parameter(ParameterSetName = 'Splat', Position = 1, ValueFromPipelineByPropertyName, HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
		        [ValidateNotNullOrEmpty()]
		        [Alias('Prefix')]
		        [String]$UnicodePrefix,
		        [Parameter(HelpMessage = 'Return the formatted message instead of writing it to the console.')]
		        [Switch]$PassThru
		    )
		    process {
		        if ($InputObject) {
		            Invoke-Debug @InputObject;
		            return;
		        }
		        $Local:Params = @{
		            PSPrefix    = if ($UnicodePrefix) { $UnicodePrefix } else { '🐛' };
		            PSMessage   = $Message;
		            PSColour    = 'Magenta';
		            ShouldWrite = $Global:Logging.Debug;
		            PassThru    = $PassThru;
		        };
		        Invoke-Write @Local:Params;
		    }
		}
		function Invoke-Info {
		    [CmdletBinding(PositionalBinding, DefaultParameterSetName = 'Splat')]
		    param(
		        [Parameter(ParameterSetName = 'InputObject', Position = 0, ValueFromPipeline)]
		        [HashTable]$InputObject,
		        [Parameter(ParameterSetName = 'Splat', Position = 0, ValueFromPipelineByPropertyName, Mandatory, HelpMessage = 'The message to write to the console.')]
		        [ValidateNotNullOrEmpty()]
		        [String]$Message,
		        [Parameter(ParameterSetName = 'Splat', Position = 1, ValueFromPipelineByPropertyName, HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
		        [ValidateNotNullOrEmpty()]
		        [Alias('Prefix')]
		        [String]$UnicodePrefix,
		        [Parameter(HelpMessage = 'Return the formatted message instead of writing it to the console.')]
		        [Switch]$PassThru
		    )
		    process {
		        if ($InputObject) {
		            Invoke-Info @InputObject;
		            return;
		        }
		        $Local:Params = @{
		            PSPrefix    = if ($UnicodePrefix) { $UnicodePrefix } else { 'ℹ️' };
		            PSMessage   = $Message;
		            PSColour    = 'Cyan';
		            ShouldWrite = $Global:Logging.Information;
		            PassThru    = $PassThru;
		        };
		        Invoke-Write @Local:Params;
		    }
		}
		function Invoke-Warn {
		    [CmdletBinding(PositionalBinding, DefaultParameterSetName = 'Splat')]
		    param(
		        [Parameter(ParameterSetName = 'InputObject', Position = 0, ValueFromPipeline)]
		        [HashTable]$InputObject,
		        [Parameter(ParameterSetName = 'Splat', Position = 0, ValueFromPipelineByPropertyName, Mandatory, HelpMessage = 'The message to write to the console.')]
		        [ValidateNotNullOrEmpty()]
		        [String]$Message,
		        [Parameter(ParameterSetName = 'Splat', Position = 1, ValueFromPipelineByPropertyName, HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
		        [ValidateNotNullOrEmpty()]
		        [Alias('Prefix')]
		        [String]$UnicodePrefix
		    )
		    process {
		        if ($InputObject) {
		            Invoke-Warn @InputObject;
		            return;
		        }
		        $Local:Params = @{
		            PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { '⚠️' };
		            PSMessage = $Message;
		            PSColour = 'Yellow';
		            ShouldWrite = $Global:Logging.Warning;
		        };
		        Invoke-Write @Local:Params;
		    }
		}
		function Invoke-Error {
		    [CmdletBinding(PositionalBinding, DefaultParameterSetName = 'Splat')]
		    param(
		        [Parameter(ParameterSetName = 'InputObject', Position = 0, ValueFromPipeline)]
		        [HashTable]$InputObject,
		        [Parameter(ParameterSetName = 'Splat', Position = 0, ValueFromPipelineByPropertyName, Mandatory, HelpMessage = 'The message to write to the console.')]
		        [ValidateNotNullOrEmpty()]
		        [String]$Message,
		        [Parameter(ParameterSetName = 'Splat', Position = 1, ValueFromPipelineByPropertyName, HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
		        [ValidateNotNullOrEmpty()]
		        [Alias('Prefix')]
		        [String]$UnicodePrefix
		    )
		    process {
		        if ($InputObject) {
		            Invoke-Error @InputObject;
		            return;
		        }
		        $Local:Params = @{
		            PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { '❌' };
		            PSMessage = $Message;
		            PSColour = 'Red';
		            ShouldWrite = $Global:Logging.Error;
		        };
		        Invoke-Write @Local:Params;
		    }
		}
		function Invoke-Timeout {
		    [CmdletBinding()]
		    param (
		        [Parameter(Mandatory, HelpMessage = 'The timeout in milliseconds.')]
		        [ValidateNotNullOrEmpty()]
		        [Int]$Timeout,
		        [Parameter(Mandatory, HelpMessage = 'The message to write to the console.')]
		        [ValidateNotNullOrEmpty()]
		        [String]$Activity,
		        [Parameter(Mandatory, HelpMessage = 'The format string to use when writing the status message, must contain a single placeholder for the time left in seconds.')]
		        [ValidateNotNullOrEmpty()]
		        [String]$StatusMessage,
		        [Parameter(HelpMessage = 'The ScriptBlock to invoke when the timeout is reached and wasn''t cancelled.')]
		        [ScriptBlock]$TimeoutScript,
		        [Parameter(ParameterSetName = 'Cancellable', HelpMessage = 'The ScriptBlock to invoke if the timeout was cancelled.')]
		        [ScriptBlock]$CancelScript,
		        [Parameter(ParameterSetName = 'Cancellable', HelpMessage = 'If the timeout is cancellable.')]
		        [Switch]$AllowCancel
		    )
		    process {
		        $Host.UI.RawUI.FlushInputBuffer();
		        [String]$Local:Prefix = if ($AllowCancel) { '⏳' } else { '⏲️' };
		        if ($AllowCancel) {
		            Invoke-Info -Message "$Activity is cancellable, press any key to cancel." -UnicodePrefix $Local:Prefix;
		        }
		        [TimeSpan]$Local:TimeInterval = [TimeSpan]::FromMilliseconds(50);
		        [TimeSpan]$Local:TimeLeft = [TimeSpan]::FromSeconds($Timeout);
		        do {
		            [DateTime]$Local:StartAt = Get-Date;
		            if ($AllowCancel -and [Console]::KeyAvailable) {
		                Invoke-Debug -Message 'Timeout cancelled by user.';
		                break;
		            }
		            Write-Progress `
		                -Activity $Activity `
		                -Status ($StatusMessage -f ([Math]::Floor($Local:TimeLeft.TotalSeconds))) `
		                -PercentComplete ($Local:TimeLeft.TotalMilliseconds / ($Timeout * 10)) `
		                -Completed:($Local:TimeLeft.TotalMilliseconds -eq 0)
		            [TimeSpan]$Local:ElaspedTime = (Get-Date) - $Local:StartAt;
		            [TimeSpan]$Local:IntervalMinusElasped = ($Local:TimeInterval - $Local:ElaspedTime);
		            if ($Local:IntervalMinusElasped.TotalMilliseconds -gt 0) {
		                $Local:TimeLeft -= $Local:IntervalMinusElasped;
		                Start-Sleep -Milliseconds $Local:IntervalMinusElasped.TotalMilliseconds;
		            } else {
		                $Local:TimeLeft -= $Local:ElaspedTime;
		            }
		        } while ($Local:TimeLeft.TotalMilliseconds -gt 0)
		        Invoke-Debug "Finished waiting for $Activity, time left: $Local:TimeLeft.";
		        if ($Local:TimeLeft -le 0) {
		            Invoke-Verbose -Message 'Timeout reached, invoking timeout script if one is present.' -UnicodePrefix $Local:Prefix;
		            if ($TimeoutScript) {
		                & $TimeoutScript;
		            }
		        } elseif ($AllowCancel) {
		            Invoke-Verbose -Message 'Timeout cancelled, invoking cancel script if one is present.' -UnicodePrefix $Local:Prefix;
		            if ($CancelScript) {
		                & $CancelScript;
		            }
		        }
		        Write-Progress -Activity $Activity -Completed;
		    }
		}
		function Invoke-Progress {
		    Param(
		        [Parameter(HelpMessage = 'The ID of the progress bar, used to display multiple progress bars at once.')]
		        [Int]$Id = 0,
		        [Parameter(HelpMessage = 'The activity to display in the progress bar.')]
		        [String]$Activity,
		        [Parameter(HelpMessage = '
		        The status message to display in the progress bar.
		        This is formatted with three placeholders:
		            The current completion percentage.
		            The index of the item being processed.
		            The total number of items being processed.
		        ')]
		        [String]$Status,
		        [Parameter(Mandatory, HelpMessage = 'The ScriptBlock which returns the items to process.')]
		        [ValidateNotNull()]
		        [ScriptBlock]$Get,
		        [Parameter(Mandatory, HelpMessage = 'The ScriptBlock to process each item.')]
		        [ValidateNotNull()]
		        [ScriptBlock]$Process,
		        [Parameter(HelpMessage = 'The ScriptBlock that formats the items name for the progress bar.')]
		        [ValidateNotNull()]
		        [ScriptBlock]$Format,
		        [Parameter(HelpMessage = 'The ScriptBlock to invoke when an item fails to process.')]
		        [ScriptBlock]$FailedProcessItem
		    )
		    begin { Enter-Scope; }
		    end { Exit-Scope; }
		    process {
		        if (-not $Activity) {
		            $Local:FuncName = (Get-PSCallStack)[1].InvocationInfo.MyCommand.Name;
		            $Activity = if (-not $Local:FuncName) {
		                'Main';
		            } else { $Local:FuncName; }
		        }
		        Write-Progress -Id:$Id -Activity:$Activity -CurrentOperation 'Getting items...' -PercentComplete 0;
		        [Object[]]$Local:InputItems = $Get.InvokeReturnAsIs();
		        Write-Progress -Id:$Id -Activity:$Activity -PercentComplete 1;
		        if ($null -eq $Local:InputItems -or $Local:InputItems.Count -eq 0) {
		            Write-Progress -Id:$Id -Activity:$Activity -Status "No items found." -PercentComplete 100 -Completed;
		            return;
		        } else {
		            Write-Progress -Id:$Id -Activity:$Activity -Status "Processing $($Local:InputItems.Count) items...";
		        }
		        [System.Collections.IList]$Local:FailedItems = New-Object System.Collections.Generic.List[System.Object];
		        [Double]$Local:PercentPerItem = 99 / $Local:InputItems.Count;
		        [Double]$Local:PercentComplete = 0;
		        [TimeSpan]$Local:TotalTime = [TimeSpan]::FromSeconds(0);
		        [Int]$Local:ItemsProcessed = 0;
		        foreach ($Item in $Local:InputItems) {
		            [String]$ItemName;
		            [TimeSpan]$Local:TimeTaken = (Measure-ElaspedTime {
		                $ItemName = if ($Format) { $Format.InvokeReturnAsIs($Item) } else { $Item; };
		            });
		            $Local:TotalTime += $Local:TimeTaken;
		            $Local:ItemsProcessed++;
		            $Local:AverageTimePerItem = $Local:TotalTime / $Local:ItemsProcessed;
		            $Local:ItemsRemaining = $Local:InputItems.Count - $Local:ItemsProcessed;
		            $Local:EstimatedTimeRemaining = $Local:AverageTimePerItem * $Local:ItemsRemaining
		            Invoke-Debug "Items remaining: $Local:ItemsRemaining";
		            Invoke-Debug "Average time per item: $Local:AverageTimePerItem";
		            Invoke-Debug "Estimated time remaining: $Local:EstimatedTimeRemaining";
		            $Local:Params = @{
		                Id = $Id;
		                Activity = $Activity;
		                CurrentOperation = "Processing [$ItemName]...";
		                SecondsRemaining = $Local:EstimatedTimeRemaining.TotalSeconds;
		                PercentComplete = [Math]::Ceiling($Local:PercentComplete);
		            };
		            if ($Status) {
		                $Local:Params.Status = ($Status -f @($Local:PercentComplete, ($Local:InputItems.IndexOf($Item) + 1), $Local:InputItems.Count));
		            }
		            Write-Progress @Local:Params;
		            try {
		                $ErrorActionPreference = "Stop";
		                $Process.InvokeReturnAsIs($Item);
		            } catch {
		                Invoke-Warn "Failed to process item [$ItemName]";
		                Invoke-Debug -Message "Due to reason - $($_.Exception.Message)";
		                try {
		                    $ErrorActionPreference = "Stop";
		                    if ($null -eq $FailedProcessItem) {
		                        $Local:FailedItems.Add($Item);
		                    } else { $FailedProcessItem.InvokeReturnAsIs($Item); }
		                } catch {
		                    Invoke-Warn "Failed to process item [$ItemName] in failed process item block";
		                }
		            }
		            $Local:PercentComplete += $Local:PercentPerItem;
		        }
		        Write-Progress -Id:$Id -Activity:$Activity -PercentComplete 100 -Completed;
		        if ($Local:FailedItems.Count -gt 0) {
		            Invoke-Warn "Failed to process $($Local:FailedItems.Count) items";
		            Invoke-Warn "Failed items: `n`t$($Local:FailedItems -join "`n`t")";
		        }
		    }
		}
		Export-ModuleMember -Function Test-SupportsUnicode, Test-SupportsColour, Invoke-Write, Invoke-Verbose, Invoke-Debug, Invoke-Info, Invoke-Warn, Invoke-Error, Format-Error, Invoke-Timeout, Invoke-Progress;
    };`
	"01-Scope" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
		[System.Collections.Stack]$Script:InvocationStack = [System.Collections.Stack]::new();
		[String]$Script:Tab = "  ";
		function Get-Stack {
		    Get-Variable -Name 'InvocationStack' -ValueOnly;
		}
		function Get-StackTop {;
		    return (Get-Stack).Peek()
		}
		function Format-ScopeName([Parameter(Mandatory)][Switch]$IsExit) {
		    [String]$Local:CurrentScope = (Get-StackTop).Invocation.MyCommand.Name;
		    [String[]]$Local:PreviousScopes = (Get-Stack).GetEnumerator() | Select-Object -Skip 1 | ForEach-Object { $_.Invocation.MyCommand.Name } | Sort-Object -Descending;
		    [String]$Local:Scope = "$($Local:PreviousScopes -join ' > ')$(if ($Local:PreviousScopes.Count -gt 0) { if ($IsExit) { ' < ' } else { ' > ' } })$Local:CurrentScope";
		    return $Local:Scope;
		}
		function Format-Parameters(
		    [Parameter()]
		    [String[]]$IgnoreParams = @(),
		    [Parameter()]
		    [HashTable]$ArgumentFormatter
		) {
		    [System.Collections.IDictionary]$Local:Params = (Get-StackTop).Invocation.BoundParameters;
		    if ($null -ne $Local:Params -and $Local:Params.Count -gt 0) {
		        [String]$Local:ParamsFormatted = ($Local:Params.GetEnumerator() `
		            | Where-Object { $_.Key -notin $IgnoreParams } `
		            | ForEach-Object {
		                $Local:Formatter = $ArgumentFormatter[$_.Key];
		                $Local:FormattedValue = Format-Variable -Value:$_.Value -Formatter:$Local:Formatter;
		                "$($_.Key) = $Local:FormattedValue";
		            }) `
		            -join "`n";
		        return "$Local:ParamsFormatted";
		    }
		    return $null;
		}
		function Format-Variable(
		    [Parameter()]
		    [Object]$Value,
		    [Parameter()]
		    [ScriptBlock]$Formatter,
		    [Parameter(DontShow)]
		    [Int]$CallDepth = 0,
		    [Parameter(DontShow)]
		    [Switch]$Appending
		) {
		    [String]$Local:FullIndent = $Script:Tab * ($CallDepth + 1);
		    [String]$Local:AppendingIndent = if (-not $Appending -and $CallDepth -gt 0) { $Local:FullIndent } else { '' };
		    [String]$Local:EndingIndent = $Script:Tab * $CallDepth;
		    if ($null -ne $Value) {
		        [String]$Local:FormattedValue = switch ($Value) {
		            { $Value -is [Array] } {
		                [String[]]$Private:Values = $Value | ForEach-Object { Format-Variable -Value:$_ -Formatter:$Formatter -CallDepth:($CallDepth + 1) -Appending; };
		                if ($Private:Values.Count -eq 0) {
		                    return "$Local:AppendingIndent[]";
		                }
		                @"
$Local:AppendingIndent[
$Local:FullIndent$($Private:Values -join ",`n$Local:FullIndent")
$Local:EndingIndent]
"@;
		                break;
		            }
		            { $Value -is [HashTable] } {
		                [String[]]$Private:Pairs = $Value.GetEnumerator() | ForEach-Object {
		                    $Private:Key = $_.Key;
		                    $Private:Value = $_.Value;
		                    "$Private:Key = $(Format-Variable -Value:$Private:Value -Formatter:$Formatter -CallDepth:($CallDepth + 1) -Appending)"
		                };
		                if ($Private:Pairs.Count -eq 0) {
		                    return "$Local:AppendingIndent{}";
		                }
		                @"
$Local:AppendingIndent{
$Local:FullIndent$($Private:Pairs -join "`n$Local:FullIndent")
$Local:EndingIndent}
"@;
		                break;
		            }
		            default {
		                if ($null -ne $Formatter) {
		                    $Formatter.InvokeWithContext($null, [PSVariable]::new('_', $Value));
		                } else {
		                    $Value;
		                }
		                break;
		            }
		        }
		        return $Local:FormattedValue;
		    };
		    return $null;
		}
		function Enter-Scope(
		    [Parameter()][ValidateNotNull()]
		    [String[]]$IgnoreParams = @(),
		    [Parameter()]
		    [ValidateNotNull()]
		    [System.Management.Automation.InvocationInfo]$Invocation = (Get-PSCallStack)[0].InvocationInfo, # Get's the callers invocation info.
		    [Parameter()]
		    [HashTable]$ArgumentFormatter,
		    [Parameter()]
		    [Switch]$PassThru
		) {
		    (Get-Stack).Push(@{ Invocation = $Invocation; StopWatch = [System.Diagnostics.Stopwatch]::StartNew(); });
		    if (-not $Global:Logging.Verbose) { return; } # If we aren't logging don't bother with the rest of the function.
		    if ($null -eq $ArgumentFormatter) {
		        $ArgumentFormatter = @{};
		    }
		    [String]$Local:ScopeName = Format-ScopeName -IsExit:$False;
		    [String]$Local:ParamsFormatted = Format-Parameters -IgnoreParams:$IgnoreParams -ArgumentFormatter:$ArgumentFormatter;
		    @{
		        PSMessage   = "$Local:ScopeName$(if ($Local:ParamsFormatted) { "`n$Local:ParamsFormatted" })";
		        PSColour    = 'Blue';
		        PSPrefix    = '❯❯';
		        ShouldWrite = $Global:Logging.Verbose;
		        PassThru    = $PassThru;
		    } | Invoke-Write;
		}
		function Exit-Scope(
		    [Parameter()]
		    [Object]$ReturnValue
		) {
		    [System.Diagnostics.Stopwatch]$Local:StopWatch = (Get-StackTop).StopWatch;
		    $Local:StopWatch.Stop();
		    if ($Global:Logging.Verbose) {
		        if ($null -eq $ArgumentFormatter) {
		            $ArgumentFormatter = @{};
		        }
		        [String]$Local:ExecutionTime = "Execution Time: $($Local:StopWatch.ElapsedMilliseconds)ms";
		        [String]$Local:ScopeName = Format-ScopeName -IsExit:$True;
		        [String]$Local:ReturnValueFormatted = Format-Variable -Value:$ReturnValue;
		        [String]$Local:Message = $Local:ScopeName;
		        if ($Local:ExecutionTime) {
		            $Local:Message += "`n$Local:ExecutionTime";
		        }
		        if ($Local:ReturnValueFormatted) {
		            $Local:Message += "`n$Local:ReturnValueFormatted";
		        }
		        @{
		            PSMessage   = $Local:Message;
		            PSColour    = 'Blue';
		            PSPrefix    = '❮❮';
		            ShouldWrite = $Global:Logging.Verbose;
		        } | Invoke-Write;
		    }
		    (Get-Stack).Pop() | Out-Null;
		}
		Export-ModuleMember -Function Get-StackTop, Format-Parameters, Format-Variable, Format-ScopeName, Enter-Scope, Exit-Scope;
    };`
	"02-Event" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
		[HashTable]$Script:Events = @{};
		enum Priority {
		    Low
		    Normal
		    High
		}
		class Subscription {
		    [GUID]$Guid;
		    [Type]$EventType;
		    [Priority]$Priority;
		    [ScriptBlock]$Callback;
		    Subscription([Type]$EventType, [ScriptBlock]$Callback) {
		        [Subscription]::new($EventType, [Priority]::Normal, [ScriptBlock]$Callback);
		    }
		    Subscription([Type]$EventType, [Priority]$Priority, [ScriptBlock]$Callback) {
		        $this.Guid = [GUID]::NewGuid()
		        $this.EventType = $EventType
		        $this.Priority = $Priority
		        $this.Callback = $Callback
		    }
		}
		class ByPriority: System.Collections.Generic.IComparer[Subscription] {
		    ByPriority() { }
		    [Int] Compare([Subscription]$a, [Subscription]$b) {
		        [Int]$OneValue = [Int]$a.Priority;
		        [Int]$TwoValue = [Int]$b.Priority;
		        if ($OneValue -eq $TwoValue) {
		            return 0;
		        }
		        if ($OneValue -lt $TwoValue) {
		            return -1;
		        }
		        return 1;
		    }
		}
		class EventRegistration {
		    [Type]$EventType;
		    [System.Collections.Generic.SortedSet[Subscription]]$Subscriptions;
		    EventRegistration([Type]$EventType) {
		        $this.EventType = $EventType;
		    }
		    [Guid] Subscribe([Subscription]$Subscription) {
		        if ($null -eq $this.Subscriptions) {
		            $this.Subscriptions = [System.Collections.Generic.SortedSet[Subscription]]::new([ByPriority]::new());
		        }
		        $this.Subscriptions.Add($Subscription);
		        return $this.Subscriptions.Guid;
		    }
		    [Boolean] Unsubscribe([Guid]$Guid) {
		        if ($null -eq $this.Subscriptions -or $this.Subscriptions.Count -eq 0) {
		            return $false;
		        }
		        [Int]$Private:Index = $this.Subscriptions.FindIndex({ param($Subscription) $Subscription.Guid -eq $Guid });
		        if ($Private:Index -eq -1) {
		            return $false;
		        }
		        $this.Subscriptions.RemoveAt($Private:Index);
		        return $true;
		    }
		    [Void] Dispatch([Object]$EventInstance) {
		        foreach ($Subscription in $this.Subscriptions) {
		            $Subscription.Callback.Invoke($EventInstance)
		        }
		    }
		    [Void] Clear() {
		        $this.Subscriptions.Clear();
		    }
		}
		class Event { }
		function Register-EventSubscription {
		    param(
		        [Type]$EventType,
		        [Priority]$Priority = [Priority]::Normal,
		        [ScriptBlock]$Callback
		    )
		    [Subscription]$Private:Subscription = [Subscription]::new($EventType, $Priority, $Callback);
		    $Script:Events[$EventType].Subscribe($Private:Subscription);
		    return $Private:Subscription.Guid;
		}
		function Submit-Event {
		    param([Object]$EventInstance)
		    $Script:Events[$EventInstance.GetType()].Dispatch($EventInstance)
		}
		function Unregister-EventSubscription {
		    param(
		        [Type]$EventType,
		        [Int]$Id
		    )
		    $Script:Events[$EventName].Unsubscribe($Id)
		}
		function Register-Event {
		    param(
		        [Type]$EventType
		    )
		    $Script:Events[$EventType] = [EventRegistration]::new($EventType)
		}
		function Get-Event {
		    param(
		        [Parameter()]
		        [Type[]]$EventType
		    )
		    if ($EventType) {
		        return $Script:Events[$EventType]
		    } else {
		        return $Script:Events
		    }
		}
		Export-Types -Types @(
		    [Priority],
		    [Subscription],
		    [ByPriority],
		    [EventRegistration],
		    [Event]
		)
    };`
	"02-Exit" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
		[HashTable]$Global:ExitHandlers = @{};
		[HashTable]$Global:ExitCodes = @{};
		[Boolean]$Global:ExitHandlersRun = $false;
		function Invoke-Handlers([switch]$IsFailure) {
		    if ($Global:ExitHandlersRun) {
		        Invoke-Debug -Message 'Exit handlers already run, skipping...';
		        return;
		    }
		    foreach ($Local:ExitHandlerName in $Global:ExitHandlers.Keys) {
		        [PSCustomObject]$Local:ExitHandler = $Global:ExitHandlers[$Local:ExitHandlerName];
		        if ($Local:ExitHandler.OnlyFailure -and (-not $IsFailure)) {
		            continue;
		        }
		        Invoke-Debug -Message "Invoking exit handler '$Local:ExitHandlerName'...";
		        try {
		            Invoke-Command -ScriptBlock $Local:ExitHandler.Script;
		        }
		        catch {
		            Invoke-Warn "Failed to invoke exit handler '$Local:ExitHandlerName': $_";
		        }
		    }
		    $Global:ExitHandlersRun = $true;
		}
		function Invoke-FailedExit {
		    [CmdletBinding()]
		    param (
		        [Parameter(Mandatory, HelpMessage = 'The exit code to return.')]
		        [ValidateNotNullOrEmpty()]
		        [Int]$ExitCode,
		        [Parameter(HelpMessage = 'The error record that caused the exit, if any.')]
		        [System.Management.Automation.ErrorRecord]$ErrorRecord,
		        [Parameter()]
		        [ValidateNotNullOrEmpty()]
		        [Switch]$DontExit,
		        [Parameter()]
		        [String[]]$FormatArgs,
		        [Parameter(DontShow)]
		        [System.Management.Automation.Cmdlet]$CallingCmdlet = $PSCmdlet
		    )
		    [String]$Local:ExitDescription = $Global:ExitCodes[$ExitCode];
		    if ($null -ne $Local:ExitDescription -and $Local:ExitDescription.Length -gt 0) {
		        if ($FormatArgs) {
		            [String]$Local:ExitDescription = $Local:ExitDescription -f $FormatArgs;
		        }
		        Invoke-Error $Local:ExitDescription;
		    }
		    elseif ($ExitCode -ne 0 -and $ExitCode -ne 9999) {
		        Invoke-Warn "No exit description found for code '$ExitCode'";
		    }
		    elseif ($ExitCode -lt 1000) {
		        Invoke-FailedExit -ExitCode $Script:INVALID_ERROR_CODE -FormatArgs $ExitCode;
		    }
		    if ($ErrorRecord) {
		        [System.Exception]$Local:DeepestException = $ErrorRecord.Exception;
		        [String]$Local:DeepestMessage = $Local:DeepestException.Message;
		        [System.Management.Automation.InvocationInfo]$Local:DeepestInvocationInfo = $ErrorRecord.InvocationInfo;
		        while ($Local:DeepestException.InnerException) {
		            Invoke-Debug "Getting inner exception... (Current: $Local:DeepestException)";
		            Invoke-Debug "Inner exception: $($Local:DeepestException.InnerException)";
		            if (-not $Local:DeepestException.InnerException.ErrorRecord) {
		                Invoke-Debug 'Inner exception has no error record, breaking to keep the current exceptions information...';
		                break;
		            }
		            $Local:DeepestException = $Local:DeepestException.InnerException;
		            if ($Local:DeepestException.Message) {
		                $Local:DeepestMessage = $Local:DeepestException.Message;
		            }
		            if ($Local:DeepestException.ErrorRecord.InvocationInfo) {
		                $Local:DeepestInvocationInfo = $Local:DeepestException.ErrorRecord.InvocationInfo;
		            }
		        }
		        if ($Local:DeepestInvocationInfo) {
		            Format-Error -InvocationInfo $Local:DeepestInvocationInfo -Message $Local:DeepestMessage;
		        }
		        elseif ($Local:DeepestMessage) {
		            Invoke-Error -Message $Local:DeepestMessage;
		        }
		    }
		    Invoke-Handlers -IsFailure:($ExitCode -ne 0);
		    if (-not $DontExit) {
		        if (-not $Local:DeepestException) {
		            [System.Exception]$Local:DeepestException = [System.Exception]::new('Failed Exit');
		        }
		        if ($null -eq $Local:DeepestException.ErrorRecord.CategoryInfo.Category) {
		            [System.Management.Automation.ErrorCategory]$Local:Catagory = [System.Management.Automation.ErrorCategory]::NotSpecified;
		        }
		        else {
		            [System.Management.Automation.ErrorCategory]$Local:Catagory = $Local:DeepestException.ErrorRecord.CategoryInfo.Category;
		        }
		        [System.Management.Automation.ErrorRecord]$Local:ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
		            [System.Exception]$Local:DeepestException,
		            'FailedExit',
		            $Local:Catagory,
		            $ExitCode
		        );
		        if ($Local:DeepestException.ErrorRecord) {
		            $Global:Error.Add($ErrorRecord);
		            $Global:Error.Add($Local:DeepestException.ErrorRecord);
		        }
		        $CallingCmdlet.ThrowTerminatingError($Local:ErrorRecord);
		    }
		}
		function Invoke-QuickExit {
		    Invoke-Handlers -IsFailure:$False;
		    [System.Management.Automation.ErrorRecord]$Local:ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
		        [System.Exception]::new('Quick Exit'),
		        'QuickExit',
		        [System.Management.Automation.ErrorCategory]::NotSpecified,
		        $null
		    );
		    throw $Local:ErrorRecord;
		}
		function Restart-Script {
		    Invoke-Handlers -IsFailure:$False;
		    Invoke-Info 'Restarting script...';
		    [System.Management.Automation.ErrorRecord]$Local:ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
		        [System.Exception]::new('Restart Script'),
		        'RestartScript',
		        [System.Management.Automation.ErrorCategory]::NotSpecified,
		        $null
		    );
		    throw $Local:ErrorRecord;
		}
		function Register-ExitHandler {
		    [CmdletBinding()]
		    param (
		        [Parameter(Mandatory)]
		        [ValidateNotNullOrEmpty()]
		        [String]$Name,
		        [Parameter(Mandatory)]
		        [ValidateNotNullOrEmpty()]
		        [ScriptBlock]$ExitHandler,
		        [switch]$OnlyFailure
		    )
		    [String]$Local:TrimmedName = $Name.Trim();
		    [PSCustomObject]$Local:Value = @{ OnlyFailure = $OnlyFailure; Script = $ExitHandler };
		    Invoke-Debug "Registering exit handler '$Local:TrimmedName'";
		    if ($Global:ExitHandlers[$Local:TrimmedName]) {
		        Invoke-Warn "Exit handler '$Local:TrimmedName' already registered, overwriting...";
		        $Global:ExitHandlers[$Local:TrimmedName] = $Local:Value;
		    }
		    else {
		        $Global:ExitHandlers.add($Local:TrimmedName, $Local:Value);
		    }
		}
		function Register-ExitCode {
		    [CmdletBinding()]
		    param (
		        [Parameter(Mandatory)]
		        [ValidateNotNullOrEmpty()]
		        [String]$Description
		    )
		    $Local:TrimmedDescription = $Description.Trim();
		    $Local:ExitCode = $Global:ExitCodes | Where-Object { $_.Value -eq $Local:TrimmedDescription };
		    if (-not $Local:ExitCode) {
		        $Local:ExitCode = $Global:ExitCodes.Count + 1001;
		        Invoke-Debug "Registering exit code '$Local:ExitCode' with description '$Local:TrimmedDescription'...";
		        $Global:ExitCodes.add($Local:ExitCode, $Local:TrimmedDescription);
		    }
		    return $Local:ExitCode;
		}
		$Script:INVALID_ERROR_CODE = Register-ExitCode -Description 'Invalid error code {0}, codes must be greater than 1000';
		Export-ModuleMember -Function Invoke-Handlers, Invoke-FailedExit, Invoke-QuickExit, Register-ExitHandler, Register-ExitCode, Restart-Script;
    };`
	"05-Assert" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
		function Assert-NotNull(
		    [Parameter(ValueFromPipeline)]
		    [Object]$Object,
		    [Parameter()]
		    [String]$Message
		) {
		    if ($null -eq $Object -or $Object -eq '') {
		        if ($null -eq $Message) {
		            Invoke-Error -Message 'Object is null';
		            Invoke-FailedExit -ExitCode $Script:NULL_ARGUMENT;
		        } else {
		            Invoke-Error $Message;
		            Invoke-FailedExit -ExitCode $Script:NULL_ARGUMENT;
		        }
		    }
		}
		function Assert-Equals([Parameter(Mandatory, ValueFromPipeline)][Object]$Object, [Parameter(Mandatory)][Object]$Expected, [String]$Message) {
		    if ($Object -ne $Expected) {
		        if ($null -eq $Message) {
		            Invoke-Error -Message "Object [$Object] does not equal expected value [$Expected]";
		            Invoke-FailedExit -ExitCode $Script:FAILED_EXPECTED_VALUE;
		        }
		        else {
		            Invoke-Error -Message $Message;
		            Invoke-FailedExit -ExitCode $Script:FAILED_EXPECTED_VALUE;
		        }
		    }
		}
		Export-ModuleMember -Function Assert-NotNull,Assert-Equals;
    };`
	"05-Ensure" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
		$Script:NOT_ADMINISTRATOR = Register-ExitCode -Description @'
Not running as administrator!
Please re-run your terminal session as Administrator, and try again.
'@;
		function Invoke-EnsureAdministrator {
		    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
		        Invoke-FailedExit -ExitCode $Script:NOT_ADMINISTRATOR;
		    }
		    Invoke-Verbose -Message 'Running as administrator.';
		}
		$Script:NOT_USER = Register-ExitCode -Description "Not running as user!`nPlease re-run your terminal session as your normal User, and try again.";
		function Invoke-EnsureUser {
		    if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
		        Invoke-FailedExit -ExitCode $Script:NOT_USER;
		    }
		    Invoke-Verbose -Message 'Running as user.';
		}
		$Script:UNABLE_TO_INSTALL_MODULE = Register-ExitCode -Description 'Unable to install module {0}';
		$Script:UNABLE_TO_IMPORT_MODULE = Register-ExitCode -Description 'Unable to import module {0}';
		$Script:UNABLE_TO_UPDATE_MODULE = Register-ExitCode -Description 'Unable to update module {0}';
		$Script:MODULE_NOT_INSTALLED = Register-ExitCode -Description 'Module not installed and no-install is set.';
		$Script:UNABLE_TO_FIND_MODULE = Register-ExitCode -Description 'Unable to find module {0}.';
		$Script:ImportedModules = [System.Collections.Generic.List[String]]::new();
		function Invoke-EnsureModule {
		    [CmdletBinding()]
		    param (
		        [Parameter(Mandatory)]
		        [ValidateNotNullOrEmpty()]
		        [ValidateScript({
		                $Local:NotValid = $_ | Where-Object {
		                    $Local:IsString = $_ -is [String];
		                    $Local:IsHashTable = $_ -is [HashTable] -and $_.Keys.Contains('Name');
		                    -not ($Local:IsString -or $Local:IsHashTable);
		                };
		                $Local:NotValid.Count -eq 0;
		            })]
		        [Object[]]$Modules
		    )
		    begin {
		        Enter-Scope;
		        if (-not $Script:SatisfiedModules) {
		            [HashTable]$Script:SatisfiedModules = [HashTable]::new();
		        }
		    }
		    end { Exit-Scope; }
		    process {
		        $ErrorActionPreference = 'Stop';
		        if (-not (Test-NetworkConnection)) {
		            Invoke-Warn 'No network connection, some modules may not be installed.';
		            return;
		        };
		        if (-not $Script:CheckedNuGet) {
		            try {
		                $ErrorActionPreference = 'Stop';
		                Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue | Out-Null;
		            }
		            catch {
		                try {
		                    Install-PackageProvider -Name NuGet -ForceBootstrap -Force -Confirm:$False;
		                    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted;
		                }
		                catch {
		                    Invoke-Warn 'Unable to install the NuGet package provider, some modules may not be installed.';
		                    return;
		                }
		            }
		            $Script:CheckedNuGet = $true;
		        }
		        foreach ($Local:Module in $Modules) {
		            $Local:InstallArgs = @{
		                AllowClobber = $true;
		                Scope        = if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { 'AllUsers' } else { 'CurrentUser' };
		                Force        = $true;
		            };
		            if ($Local:Module -is [HashTable]) {
		                [String]$Local:ModuleName = $Local:Module.Name;
		                [String]$Local:ModuleMinimumVersion = $Local:Module.MinimumVersion;
		                [Boolean]$Local:DontRemove = $Local:Module.DontRemove;
		                if ($Local:ModuleMinimumVersion) {
		                    $Local:InstallArgs.Add('MinimumVersion', $Local:ModuleMinimumVersion);
		                }
		                [Version]$Local:MinimumVersion = [Version]::Parse($Local:ModuleMinimumVersion);
		            }
		            else {
		                [String]$Local:ModuleName = $Local:Module;
		                [Boolean]$Local:DontRemove = $False;
		            }
		            [Version]$Local:PossibleSatifiedModuleVersion = $Script:SatisfiedModules[$Local:ModuleName];
		            if ($Local:PossibleSatifiedModuleVersion -and ($Local:PossibleSatifiedModuleVersion -ge $Local:MinimumVersion)) {
		                Invoke-Debug "Module '$Local:ModuleName' is already satisfied with version $Local:PossibleSatifiedModuleVersion.";
		                continue;
		            }
		            $Local:InstallArgs.Add('Name', $Local:ModuleName);
		            function Import-Module_Internal {
		                param(
		                    [String]$ModuleName,
		                    [String]$ModuleImport,
		                    [Boolean]$DontRemove
		                )
		                if (-not $DontRemove) {
		                    $Script:ImportedModules.Add($ModuleName);
		                }
		                if ($Local:AvailableModule) {
		                    Remove-Module -Name $ModuleName -Force;
		                }
		                try {
		                    if ($ModuleImport.EndsWith('.ps1')) {
		                        [PSModuleInfo]$Local:ImportedModule = Import-Module `
		                            -Name $ModuleImport `
		                            -Function * `
		                            -Variable * `
		                            -Alias * `
		                            -Global `
		                            -Force `
		                            -PassThru;
		                    }
		                    else {
		                        [PSModuleInfo]$Local:ImportedModule = Import-Module -Name $ModuleImport -Global -Force -PassThru;
		                    }
		                    Invoke-Info "Module '$ModuleName' imported with version $($Local:ImportedModule.Version).";
		                    $Script:SatisfiedModules[$ModuleName] = [Version]::Parse($Local:ImportedModule.Version);
		                }
		                catch {
		                    Invoke-FailedExit -ExitCode $Script:UNABLE_TO_IMPORT_MODULE -FormatArgs $ModuleName;
		                }
		            }
		            if (Test-Path $Local:ModuleName) {
		                Invoke-Debug "Module '$Local:ModuleName' is a local path to a module, importing...";
		                Import-Module_Internal -ModuleName:($Local:ModuleName | Split-Path -LeafBase) -ModuleImport:$Local:ModuleName -DontRemove:$Local:DontRemove;
		                continue;
		            }
		            if ($Local:ModuleName -match '^(?<owner>.+?)/(?<repo>.+?)(?:@(?<ref>.+))?$') {
		                Invoke-Debug "Module '$Local:ModuleName' is a git repository, importing...";
		                [String]$Local:Owner = $Matches.owner;
		                [String]$Local:Repo = $Matches.repo;
		                [String]$Local:Ref = $Matches.ref;
		                [String]$Local:ModuleName = Install-ModuleFromGitHub -GitHubRepo "$Local:Owner/$Local:Repo" -Branch $Local:Ref -Scope CurrentUser;
		                Import-Module_Internal -ModuleName:($Local:ModuleName | Split-Path -LeafBase) -ModuleImport:$Local:ModuleName -DontRemove:$Local:DontRemove;
		                continue;
		            }
		            $Local:CurrentImportedModule = Get-Module -Name $Local:ModuleName -ErrorAction SilentlyContinue | Sort-Object -Property Version -Descending | Select-Object -First 1;
		            $Local:AvailableModule = if (-not ($Local:CurrentImportedModule)) { Get-Module -ListAvailable -Name $Local:ModuleName -ErrorAction SilentlyContinue | Sort-Object -Property Version -Descending | Select-Object -First 1; } else { $Local:CurrentImportedModule };
		            if ($Local:AvailableModule) {
		                Invoke-Debug "Module '$Local:ModuleName' is installed with version $($Local:AvailableModule.Version).";
		                if ($Local:ModuleMinimumVersion -and $Local:AvailableModule.Version -lt $Local:ModuleMinimumVersion) {
		                    Invoke-Verbose 'Module is installed, but the version is less than the minimum version required, trying to update...';
		                    try {
		                        Update-Module -Name $Local:ModuleName -Force -RequiredVersion $Local:ModuleMinimumVersion -ErrorAction Stop;
		                        Import-Module_Internal -ModuleName:$Local:ModuleName -ModuleImport:$Local:ModuleName -DontRemove:$Local:DontRemove;
		                    }
		                    catch {
		                        if ($_.FullyQualifiedErrorId -ne 'ModuleNotInstalledUsingInstallModuleCmdlet,Update-Module') {
		                            Invoke-Error -Message "Unable to update module '$Local:ModuleName'";
		                            Invoke-FailedExit -ExitCode $Script:UNABLE_TO_UPDATE_MODULE -FormatArgs @($Local:ModuleName);
		                        }
		                        Invoke-Verbose 'Module was unable to be updated, will try to install...';
		                        [Boolean]$Local:TryInstall = $true
		                    }
		                }
		                elseif ($null -eq $Local:CurrentImportedModule -or ($Local:CurrentImportedModule.Version -lt $Local:ModuleMinimumVersion)) {
		                    Invoke-Debug "Module '$Local:ModuleName' is installed, but the version is less than the minimum version required, importing...";
		                    Import-Module_Internal -ModuleName:$Local:ModuleName -ModuleImport:$Local:ModuleName -DontRemove:$Local:DontRemove;
		                }
		                else {
		                    Invoke-Debug "Module '$Local:ModuleName' is installed, skipping...";
		                    $Script:SatisfiedModules[$Local:ModuleName] = $Local:CurrentImportedModule.Version;
		                }
		            }
		            if ($null -eq $Local:AvailableModule -or $Local:TryInstall) {
		                $Local:FoundModule = Find-Module `
		                    -Name $Local:ModuleName `
		                    -MinimumVersion:$(if ($Local:InstallArgs.MinimumVersion) { $Local:InstallArgs.MinimumVersion } else { '0.0.0' }) `
		                    -ErrorAction SilentlyContinue;
		                if ($Local:FoundModule) {
		                    Invoke-Info "Module '$Local:ModuleName' is not installed, installing...";
		                    try {
		                        $Local:FoundModule | Install-Module -AllowClobber -Scope CurrentUser -Force;
		                    }
		                    catch {
		                        Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:UNABLE_TO_INSTALL_MODULE -FormatArgs @($Local:ModuleName);
		                    }
		                    if (-not $Local:Module.RestartIfUpdated) {
		                        Import-Module_Internal -ModuleName:$Local:ModuleName -ModuleImport:$Local:ModuleName -DontRemove:$Local:DontRemove -ErrorAction SilentlyContinue;
		                    }
		                    else {
		                        Invoke-Info "Module '$Local:ModuleName' has been installed, restart script...";
		                        Restart-Script;
		                    }
		                }
		                else {
		                    Invoke-Warn "Unable to find module '$Local:ModuleName'.";
		                }
		            }
		            [PSModuleInfo]$Local:AfterEnsureModule = Get-Module -Name $Local:ModuleName -ErrorAction SilentlyContinue | Sort-Object -Property Version -Descending | Select-Object -First 1;
		            if ($null -eq $Local:AfterEnsureModule) {
		                Invoke-FailedExit -ExitCode $Script:UNABLE_TO_FIND_MODULE -FormatArgs @($Local:ModuleName);
		            }
		            elseif ($Local:CurrentImportedModule -ne $Local:AfterEnsureModule -and $Local:Module.RestartIfUpdated) {
		                Invoke-Info "Module '$Local:ModuleName' has been updated, restart script...";
		                Restart-Script;
		            }
		        }
		        Invoke-Verbose -Message 'All modules are installed.';
		    }
		}
		$Script:WifiXmlTemplate = '<?xml version="1.0"?>
		<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
		  <name>{0}</name>
		  <SSIDConfig>
		    <SSID>
		      <hex>{1}</hex>
		      <name>{0}</name>
		    </SSID>
		  </SSIDConfig>
		  <connectionType>ESS</connectionType>
		  <connectionMode>auto</connectionMode>
		  <MSM>
		    <security>
		      <authEncryption>
		        <authentication>{2}</authentication>
		        <encryption>{3}</encryption>
		        <useOneX>false</useOneX>
		      </authEncryption>
		      <sharedKey>
		        <keyType>passPhrase</keyType>
		        <protected>false</protected>
		        <keyMaterial>{4}</keyMaterial>
		      </sharedKey>
		    </security>
		  </MSM>
		</WLANProfile>
		';
		$Private:NO_CONNECTION_AFTER_SETUP = Register-ExitCode -Description 'Failed to connect to the internet after network setup.';
		function Invoke-EnsureNetwork(
		    [Parameter(HelpMessage = 'The name of the network to connect to.')]
		    [ValidateNotNullOrEmpty()]
		    [String]$Name,
		    [Parameter(HelpMessage = 'The password of the network to connect if required.')]
		    [SecureString]$Password
		) {
		    begin { Enter-Scope -Invocation $MyInvocation; }
		    end { Exit-Scope; }
		    process {
		        [Boolean]$Local:HasNetwork = (Get-NetConnectionProfile | Where-Object {
		                $Local:HasIPv4 = $_.IPv4Connectivity -eq 'Internet';
		                $Local:HasIPv6 = $_.IPv6Connectivity -eq 'Internet';
		                $Local:HasIPv4 -or $Local:HasIPv6
		            } | Measure-Object | Select-Object -ExpandProperty Count) -gt 0;
		        if ($Local:HasNetwork) {
		            Invoke-Debug 'Network is setup, skipping network setup...';
		            return $false;
		        }
		        Invoke-Info 'Network is not setup, setting up network...';
		        Invoke-WithinEphemeral {
		            [String]$Local:ProfileFile = "$Name.xml";
		            [String]$Local:SSIDHex = ($Name.ToCharArray() | ForEach-Object { '{0:X}' -f ([int]$_) }) -join '';
		            if ($Password) {
		                $Local:SecureBSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password);
		                $Local:PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($Local:SecureBSTR);
		            }
		            [Xml]$Local:XmlContent = [String]::Format($Script:WifiXmlTemplate, $Name, $SSIDHex, 'WPA2PSK', 'AES', $PlainPassword);
		            if (-not $PlainPassword) {
		                $Local:XmlContent.WLANProfile.MSM.security.RemoveChild($Local:XmlContent.WLANProfile.MSM.security.sharedKey) | Out-Null;
		            }
		            $Local:XmlContent.InnerXml | Out-File -FilePath $Local:ProfileFile -Encoding UTF8;
		            if ($WhatIfPreference) {
		                Invoke-Info -Message 'WhatIf is set, skipping network setup...';
		                return $true;
		            }
		            else {
		                Invoke-Info -Message 'Setting up network...';
		                netsh wlan add profile filename="$Local:ProfileFile" | Out-Null;
		                netsh wlan show profiles $Name key=clear | Out-Null;
		                netsh wlan connect name="$Name" | Out-Null;
		                Invoke-Info 'Waiting for network connection...'
		                $Local:RetryCount = 0;
		                while (-not (Test-Connection -Destination google.com -Count 1 -Quiet)) {
		                    If ($Local:RetryCount -ge 60) {
		                        Invoke-Error "Failed to connect to $NetworkName after 10 retries";
		                        Invoke-FailedExit -ExitCode $Private:NO_CONNECTION_AFTER_SETUP;
		                    }
		                    Start-Sleep -Seconds 1
		                    $Local:RetryCount += 1
		                }
		                Invoke-Info -Message 'Network setup successfully.';
		                return $True;
		            }
		        }
		    }
		}
		Register-ExitHandler -Name 'Remove Imported Modules' -ExitHandler {
		    if ($Script:ImportedModules.Count -lt 1) {
		        Invoke-Debug 'No additional modules were imported, skipping cleanup...';
		        return;
		    }
		    Invoke-Verbose -Prefix '♻️' -Message "Cleaning up $($Script:ImportedModules.Count) additional imported modules.";
		    Invoke-Verbose -Prefix '✅' -Message "Removed modules: `n`t$($Script:ImportedModules -join "`n`t")";
		    Remove-Module -Name $Script:ImportedModules -Force;
		};
		Export-ModuleMember -Function Invoke-EnsureAdministrator, Invoke-EnsureUser, Invoke-EnsureModule, Invoke-EnsureNetwork;
    };`
	"40-Temp" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
		function Get-NamedTempFolder {
		    Param(
		        [Parameter(Mandatory)]
		        [ValidateNotNullOrEmpty()]
		        [String]$Name,
		        [switch]$ForceEmpty
		    )
		    [String]$Local:Folder = [System.IO.Path]::GetTempPath() | Join-Path -ChildPath $Name;
		    if ($ForceEmpty -and (Test-Path $Local:Folder -PathType Container)) {
		        Invoke-Verbose -Message "Emptying temporary folder $Local:Folder...";
		        Remove-Item -Path $Local:Folder -Force -Recurse | Out-Null;
		    }
		    if (-not (Test-Path $Local:Folder -PathType Container)) {
		        Invoke-Verbose -Message "Creating temporary folder $Local:Folder...";
		        New-Item -ItemType Directory -Path $Local:Folder | Out-Null;
		    } elseif (Test-Path $Local:Folder -PathType Container) {
		        Invoke-Verbose -Message "Temporary folder $Local:Folder already exists.";
		        if ($ForceEmpty) {
		            Invoke-Verbose -Message "Emptying temporary folder $Local:Folder...";
		            Remove-Item -Path $Local:Folder -Force -Recurse | Out-Null;
		        }
		    }
		    return $Local:Folder;
		}
		function Get-UniqueTempFolder {
		    Get-NamedTempFolder -Name ([System.IO.Path]::GetRandomFileName()) -ForceEmpty;
		}
		function Invoke-WithinEphemeral {
		    Param(
		        [Parameter(Mandatory)]
		        [ValidateNotNullOrEmpty()]
		        [ScriptBlock]$ScriptBlock
		    )
		    [String]$Local:Folder = Get-UniqueTempFolder;
		    try {
		        Invoke-Verbose -Message "Executing script block within temporary folder $Local:Folder...";
		        Push-Location -Path $Local:Folder;
		        & $ScriptBlock;
		    } finally {
		        Invoke-Verbose -Message "Cleaning temporary folder $Local:Folder...";
		        Pop-Location;
		        Remove-Item -Path $Local:Folder -Force -Recurse;
		    }
		}
		Export-ModuleMember -Function Get-NamedTempFolder, Get-UniqueTempFolder, Invoke-WithinEphemeral;
    };`
	"45-PackageManager" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
		enum PackageManager {
		    Chocolatey
		    Unsupported
		}
		[PackageManager]$Script:PackageManager = switch ($env:OS) {
		    'Windows_NT' { [PackageManager]::Chocolatey };
		    default { [PackageManager]::Unsupported };
		};
		[HashTable]$Script:PackageManagerDetails = switch ($Script:PackageManager) {
		    Chocolatey {
		        @{
		            Executable = "$($env:SystemDrive)\ProgramData\Chocolatey\bin\choco.exe";
		            Commands = @{
		                List       = 'list';
		                Uninstall  = 'uninstall';
		                Install    = 'install';
		                Update     = 'upgrade';
		            }
		            Options = @{
		                Common = @('--confirm', '--limit-output', '--no-progress', '--exact');
		                Force = '--force';
		            }
		        };
		    };
		    Unsupported {
		        Invoke-Error 'Could not find a supported package manager.';
		        $null;
		    }
		};
		[Boolean]$Script:CompletedSetup = $False;
		function Local:Install-Requirements {
		    if ($Script:CompletedSetup) {
		        Invoke-Debug 'Setup already completed. Skipping...';
		        return;
		    }
		    if (-not (Test-NetworkConnection)) {
		        Invoke-Error 'No network connection detected. Skipping package manager installation.';
		        Invoke-FailedExit -ExitCode 9999;
		    }
		    @{
		        PSPrefix = '📦';
		        PSMessage = "Installing requirements for $Script:PackageManager...";
		        PSColour = 'Green';
		    } | Invoke-Write;
		    switch ($Script:PackageManager) {
		        Chocolatey {
		            if (Get-Command -Name 'choco' -ErrorAction SilentlyContinue) {
		                Invoke-Debug 'Chocolatey is already installed. Skipping installation.';
		                return
		            }
		            if (Test-Path -Path "$($env:SystemDrive)\ProgramData\chocolatey") {
		                Invoke-Debug 'Chocolatey files found, seeing if we can repair them...';
		                if (Test-Path -Path "$($env:SystemDrive)\ProgramData\chocolatey\bin\choco.exe") {
		                    Invoke-Debug 'Chocolatey bin found, should be able to refreshenv!';
		                    Invoke-Debug 'Refreshing environment variables...';
		                    Import-Module "$($env:SystemDrive)\ProgramData\chocolatey\Helpers\chocolateyProfile.psm1" -Force;
		                    refreshenv | Out-Null;
		                    return;
		                } else {
		                    Invoke-Warn 'Chocolatey bin not found, deleting folder and reinstalling...';
		                    Remove-Item -Path "$($env:SystemDrive)\ProgramData\chocolatey" -Recurse -Force;
		                }
		            }
		            Invoke-Info 'Installing Chocolatey...';
		            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'));
		        }
		        Default {}
		    }
		    [Boolean]$Script:CompletedSetup = $True;
		}
		function Test-ManagedPackage(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [String]$PackageName
		) {
		    begin { Enter-Scope; Install-Requirements; }
		    end { Exit-Scope -ReturnValue $Local:Installed; }
		    process {
		        @{
		            PSPrefix = '🔍';
		            PSMessage = "Checking if package '$PackageName' is installed...";
		            PSColour = 'Yellow';
		        } | Invoke-Write;
		        [Boolean]$Local:Installed = & $Script:PackageManagerDetails.Executable $Script:PackageManagerDetails.Commands.List $Script:PackageManagerDetails.Options.Common $PackageName;
		        Invoke-Verbose "Package '$PackageName' is $(if (-not $Local:Installed) { 'not ' })installed.";
		        return $Local:Installed;
		    }
		}
		function Install-ManagedPackage(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [String]$PackageName,
		    [Parameter()]
		    [ValidateNotNullOrEmpty()]
		    [String]$Sha256,
		    [Parameter()]
		    [ValidateNotNullOrEmpty()]
		    [Switch]$NoFail
		) {
		    begin { Enter-Scope; Install-Requirements; }
		    end { Exit-Scope; }
		    process {
		        @{
		            PSPrefix = '📦';
		            PSMessage = "Installing package '$Local:PackageName'...";
		            PSColour = 'Green';
		        } | Invoke-Write;
		        [System.Diagnostics.Process]$Local:Process = Start-Process -FilePath $Script:PackageManagerDetails.Executable -ArgumentList (@($Script:PackageManagerDetails.Commands.Install) + $Script:PackageManagerDetails.Options.Common + @($PackageName)) -NoNewWindow -PassThru -Wait;
		        if ($Local:Process.ExitCode -ne 0) {
		            Invoke-Error "There was an issue while installing $Local:PackageName.";
		            Invoke-FailedExit -ExitCode $Local:Process.ExitCode -DontExit:$NoFail;
		        }
		    }
		}
		function Uninstall-ManagedPackage() {
		}
		function Update-ManagedPackage(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [String]$PackageName
		) {
		    begin { Enter-Scope; Install-Requirements; }
		    end { Exit-Scope; }
		    process {
		        @{
		            PSPrefix = '🔄';
		            PSMessage = "Updating package '$Local:PackageName'...";
		            PSColour = 'Blue';
		        } | Invoke-Write;
		        try {
		            & $Script:PackageManagerDetails.Executable $Script:PackageManagerDetails.Commands.Update $Script:PackageManagerDetails.Options.Common $PackageName | Out-Null;
		            if ($LASTEXITCODE -ne 0) {
		                throw "Error Code: $LASTEXITCODE";
		            }
		        } catch {
		            Invoke-Error "There was an issue while updating $Local:PackageName.";
		            Invoke-Error $_.Exception.Message;
		        }
		    }
		}
		Export-ModuleMember -Function Test-ManagedPackage, Install-ManagedPackage, Uninstall-Package, Update-ManagedPackage;
    };`
	"50-Input" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
		$Script:Validations = @{
		    Email = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
		}
		[HashTable]$Script:WriteStyle = @{
		    PSColour    = 'DarkCyan';
		    PSPrefix    = '▶';
		    ShouldWrite = $true;
		};
		function Clear-HostLight (
		    [Parameter(Position = 1)]
		    [int32]$Count = 1
		) {
		    $CurrentLine = $Host.UI.RawUI.CursorPosition.Y
		    $ConsoleWidth = $Host.UI.RawUI.BufferSize.Width
		    $i = 1
		    for ($i; $i -le $Count; $i++) {
		        [Console]::SetCursorPosition(0, ($CurrentLine - $i))
		        [Console]::Write("{0,-$ConsoleWidth}" -f ' ')
		    }
		    [Console]::SetCursorPosition(0, ($CurrentLine - $Count))
		}
		function Register-CustomReadLineHandlers([Switch]$DontSaveInputs) {
		    [Object]$Local:PreviousEnterFunction = (Get-PSReadLineKeyHandler -Chord Enter).Function;
		    [Boolean]$Script:PressedEnter = $False;
		    Set-PSReadLineKeyHandler -Chord Enter -ScriptBlock {
		        Param([System.ConsoleKeyInfo]$Key, $Arg)
		        $Script:PressedEnter = $True;
		        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine($Key, $Arg);
		    };
		    [Object]$Local:PreviousCtrlCFunction = (Get-PSReadLineKeyHandler -Chord Ctrl+c).Function;
		    [Boolean]$Script:ShouldAbort = $False;
		    Set-PSReadLineKeyHandler -Chord Ctrl+c -ScriptBlock {
		        Param([System.ConsoleKeyInfo]$Key, $Arg)
		        $Script:ShouldAbort = $True;
		        [Microsoft.PowerShell.PSConsoleReadLine]::CancelLine($Key, $Arg);
		    };
		    [Int]$Script:ExtraLines = 0;
		    [ScriptBlock]$Private:EnterScriptBlock = {
		        Param([System.ConsoleKeyInfo]$Key, $Arg)
		        $Script:ExtraLines++;
		        [Microsoft.PowerShell.PSConsoleReadLine]::AddLine($Key, $Arg);
		    };
		    [Object]$Local:PreviousCtrlEnterFunction = (Get-PSReadLineKeyHandler -Chord Ctrl+Enter).Function;
		    [Object]$Local:PreviousShiftEnterFunction = (Get-PSReadLineKeyHandler -Chord Shift+Enter).Function;
		    Set-PSReadLineKeyHandler -Chord Ctrl+Enter -ScriptBlock $Private:EnterScriptBlock;
		    Set-PSReadLineKeyHandler -Chord Shift+Enter -ScriptBlock $Private:EnterScriptBlock;
		    [System.Func[String, Object]]$Local:HistoryHandler = (Get-PSReadLineOption).AddToHistoryHandler;
		    if ($DontSaveInputs) {
		        Set-PSReadLineOption -AddToHistoryHandler {
		            Param([String]$Line)
		            $False;
		        }
		    }
		    return @{
		        Enter          = $Local:PreviousEnterFunction;
		        CtrlC          = $Local:PreviousCtrlCFunction;
		        CtrlShift      = $Local:PreviousCtrlEnterFunction;
		        ShiftEnter     = $Local:PreviousShiftEnterFunction;
		        HistoryHandler = $Local:HistoryHandler;
		    }
		}
		function Unregister-CustomReadLineHandlers([HashTable]$PreviousHandlers) {
		    Set-PSReadLineKeyHandler -Chord Enter -Function $PreviousHandlers.Enter;
		    Set-PSReadLineKeyHandler -Chord Ctrl+c -Function $PreviousHandlers.CtrlC;
		    Set-PSReadLineKeyHandler -Chord Ctrl+Enter -Function $PreviousHandlers.CtrlShift;
		    Set-PSReadLineKeyHandler -Chord Shift+Enter -Function $PreviousHandlers.ShiftEnter;
		    Set-PSReadLineOption -AddToHistoryHandler $PreviousHandlers.HistoryHandler;
		}
		function Get-UserInput {
		    Param(
		        [Parameter(Mandatory)]
		        [ValidateNotNullOrEmpty()]
		        [String]$Title,
		        [Parameter(Mandatory)]
		        [ValidateNotNullOrEmpty()]
		        [Alias('Prompt')]
		        [String]$Question,
		        [Parameter(HelpMessage = 'Validation script block to validate the user input.')]
		        [ValidateNotNullOrEmpty()]
		        [ScriptBlock]$Validate,
		        [Parameter()]
		        [Switch]$AsSecureString,
		        [Parameter()]
		        [Switch]$DontSaveInputs = $AsSecureString,
		        [Parameter()]
		        [Switch]$SaveInputAsUniqueHistory,
		        [Parameter()]
		        [Switch]$AllowEmpty
		    )
		    begin { Enter-Scope; Install-Requirements; }
		    end { Exit-Scope -ReturnValue $Local:UserInput; }
		    process {
		        Invoke-Write @Script:WriteStyle -PSMessage $Title;
		        Invoke-Write @Script:WriteStyle -PSMessage $Question;
		        [HashTable]$Local:PreviousFunctions = Register-CustomReadLineHandlers -DontSaveInputs:$DontSaveInputs;
		        if ($SaveInputAsUniqueHistory) {
		            $Local:PreviousHistorySavePath = (Get-PSReadLineOption).HistorySavePath;
		            $Local:Hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$Title$Question"));
		            $Local:HashString = [System.BitConverter]::ToString($Local:Hash).Replace('-', '');
		            $Local:HashString = $Local:HashString.Substring(0, [Math]::Min(8, $Local:HashString.Length));
		            $Private:FileLocation = "$env:APPDATA\Roaming\Microsoft\Windows\PowerShell\PSReadLine\UniqueHistory-$Local:HashString.txt";
		            Set-PSReadLineOption -HistorySavePath $Private:FileLocation;
		        }
		        $Host.UI.RawUI.FlushInputBuffer();
		        Clear-HostLight -Count 0; # Clear the line buffer to get rid of the >> prompt.
		        Write-Host "`r>> " -NoNewline;
		        do {
		            [String]$Local:UserInput = ([Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($Host.Runspace, $ExecutionContext, $?)).Trim();
		            if ((-not $AllowEmpty -and -not $Local:UserInput) -or ($Validate -and (-not $Validate.InvokeWithContext($null, [PSVariable]::new('_', $Local:UserInput))))) {
		                $Local:ClearLines = if ($Local:FailedAtLeastOnce -and $Script:PressedEnter) {
		                    $Private:Value = $Script:ExtraLines + 2;
		                    $Script:ExtraLines = 0;
		                    $Private:Value;
		                }
		                else {
		                    1
		                };
		                Clear-HostLight -Count $Local:ClearLines;
		                Invoke-Write @Script:WriteStyle -PSMessage 'Invalid input, please try again...';
		                $Host.UI.Write('>> ');
		                $Local:FailedAtLeastOnce = $true;
		                $Script:PressedEnter = $false;
		            }
		            else {
		                Clear-HostLight -Count 1;
		                break;
		            }
		        } while (-not $Script:ShouldAbort);
		        Unregister-CustomReadLineHandlers -PreviousHandlers $Local:PreviousFunctions;
		        if ($Script:ShouldAbort) {
		            throw [System.Management.Automation.PipelineStoppedException]::new();
		        }
		        if ($SaveInputAsUniqueHistory) {
		            Set-PSReadLineOption -HistorySavePath $Local:PreviousHistorySavePath;
		        }
		        if ($AllowEmpty -and -not $Local:UserInput) {
		            return $null;
		        }
		        if ($AsSecureString) {
		            [SecureString]$Local:UserInput = ConvertTo-SecureString -String $Local:UserInput -AsPlainText -Force;
		        }
		        return $Local:UserInput;
		    }
		}
		function Get-UserConfirmation {
		    Param(
		        [Parameter(Mandatory)]
		        [ValidateNotNullOrEmpty()]
		        [String]$Title,
		        [Parameter(Mandatory)]
		        [ValidateNotNullOrEmpty()]
		        [String]$Question,
		        [Parameter()]
		        [ValidateNotNullOrEmpty()]
		        [Boolean]$DefaultChoice
		    )
		    $Local:DefaultChoice = if ($null -eq $DefaultChoice) { 1 } elseif ($DefaultChoice) { 0 } else { 1 };
		    $Local:Result = Get-UserSelection -Title $Title -Question $Question -Choices @('Yes', 'No') -DefaultChoice $Local:DefaultChoice;
		    switch ($Local:Result) {
		        'Yes' { $true }
		        'No' { $false }
		    }
		}
		function Get-UserSelection {
		    Param(
		        [Parameter(Mandatory)]
		        [ValidateNotNullOrEmpty()]
		        [String]$Title,
		        [Parameter(Mandatory)]
		        [ValidateNotNullOrEmpty()]
		        [String]$Question,
		        [Parameter(Mandatory)]
		        [ValidateNotNullOrEmpty()]
		        [Alias('Items')]
		        [Array]$Choices,
		        [Parameter()]
		        [Int]$DefaultChoice = 0,
		        [Parameter()]
		        [Switch]$AllowNone,
		        [Parameter()]
		        [ValidateNotNullOrEmpty()]
		        [ScriptBlock]$FormatChoice = { Param([String]$Choice) $Choice.ToString(); }
		    )
		    begin {
		        Enter-Scope;
		        Install-Requirements;
		        [HashTable]$Local:PreviousFunctions = Register-CustomReadLineHandlers -DontSaveInputs;
		        $Local:PreviousTabFunction = (Get-PSReadLineKeyHandler -Chord Tab).Function;
		        if (-not $Local:PreviousTabFunction) {
		            $Local:PreviousTabFunction = 'TabCompleteNext';
		        }
		        $Local:PreviousShiftTabFunction = (Get-PSReadLineKeyHandler -Chord Shift+Tab).Function;
		        if (-not $Local:PreviousShiftTabFunction) {
		            $Local:PreviousShiftTabFunction = 'TabCompletePrevious';
		        }
		        [String[]]$Script:ChoicesList = $Choices | ForEach-Object {
		            $Formatted = $FormatChoice.InvokeReturnAsIs($_);
		            if (-not $Formatted -or $Formatted -eq '') {
		                throw [System.ArgumentException]::new('FormatChoice script block must return a non-empty string.');
		            }
		            $Formatted;
		        };
		        Set-PSReadLineKeyHandler -Chord Tab -ScriptBlock {
		            Param([System.ConsoleKeyInfo]$Key, $Arg)
		            $Line = $null;
		            $Cursor = $null;
		            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$Line, [ref]$Cursor);
		            $MatchingInput = $Line.Substring(0, $Cursor);
		            if ($Script:PreviewingChoices -and $Line -eq $Script:PreviewingInput) {
		                if ($Script:ChoicesGoneThrough -eq $Script:MatchedChoices.Count - 1) {
		                    $Script:ChoicesGoneThrough = 0;
		                }
		                else {
		                    $Script:ChoicesGoneThrough++;
		                }
		                $Script:PreviewingInput = $Script:MatchedChoices[$Script:ChoicesGoneThrough];
		                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $MatchingInput.Length, $Script:PreviewingInput);
		                return;
		            }
		            $Script:PreviewingChoices = $false;
		            $Script:PreviewingInput = $null;
		            $Script:ChoicesGoneThrough = 0;
		            $Script:MatchedChoices = $Script:ChoicesList | Where-Object { $_ -like "$MatchingInput*" };
		            if ($Script:MatchedChoices.Count -gt 1) {
		                $Script:PreviewingChoices = $true;
		                $Script:PreviewingInput = $Script:MatchedChoices[$Script:ChoicesGoneThrough];
		                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $MatchingInput.Length, $Script:MatchedChoices[$Script:ChoicesGoneThrough]);
		            }
		            elseif ($Script:MatchedChoices.Count -eq 1) {
		                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $MatchingInput.Length, $Script:MatchedChoices);
		            }
		        }
		        Set-PSReadLineKeyHandler -Chord Shift+Tab -ScriptBlock {
		            Param([System.ConsoleKeyInfo]$Key, $Arg)
		            $Line = $null;
		            $Cursor = $null;
		            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$Line, [ref]$Cursor);
		            $MatchingInput = $Line.Substring(0, $Cursor);
		            if ($Script:PreviewingChoices -and $Line -eq $Script:PreviewingInput) {
		                if ($Script:ChoicesGoneThrough -eq 0) {
		                    $Script:ChoicesGoneThrough = $Script:MatchedChoices.Count - 1;
		                }
		                else {
		                    $Script:ChoicesGoneThrough--;
		                }
		                $Script:PreviewingInput = $Script:MatchedChoices[$Script:ChoicesGoneThrough];
		                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $MatchingInput.Length, $Script:PreviewingInput);
		                return;
		            }
		        };
		    }
		    process {
		        Invoke-Write @Script:WriteStyle -PSMessage $Title;
		        Invoke-Write @Script:WriteStyle -PSMessage $Question;
		        [Boolean]$Local:FirstRun = $true;
		        $Host.UI.RawUI.FlushInputBuffer();
		        Clear-HostLight -Count 0; # Clear the line buffer to get rid of the >> prompt.
		        Invoke-Write @Script:WriteStyle -PSMessage "Enter one of the following: $($ChoicesList -join ', ')";
		        Write-Host '>> ' -NoNewline;
		        if ($null -ne $DefaultChoice) {
		            Write-Host "$($PSStyle.Foreground.FromRgb(40, 44, 52))$($ChoicesList[$DefaultChoice])" -NoNewline;
		        }
		        Write-Host "`r>> " -NoNewline;
		        do {
		            $Local:Selection = ([Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($Host.Runspace, $ExecutionContext, $?)).Trim();
		            if (-not $Local:Selection -and $Local:FirstRun -and $null -ne $DefaultChoice) {
		                $Local:Selection = $Choices[$DefaultChoice];
		                Clear-HostLight -Count 1;
		            }
		            elseif ($Local:Selection -notin $ChoicesList) {
		                $Local:ClearLines = if ($Local:FailedAtLeastOnce -and $Script:PressedEnter) { 2 } else { 1 };
		                Clear-HostLight -Count $Local:ClearLines;
		                Invoke-Write @Script:WriteStyle -PSMessage 'Invalid selection, please try again...';
		                $Host.UI.Write('>> ');
		                $Local:FailedAtLeastOnce = $true;
		                $Script:PressedEnter = $false;
		            }
		            $Local:FirstRun = $false;
		        } while ($Local:Selection -notin $ChoicesList -and -not $Script:ShouldAbort);
		        if ($Script:ShouldAbort) {
		            if (-not $AllowNone) {
		                throw [System.Management.Automation.PipelineStoppedException]::new();
		            }
		            else {
		                return $null;
		            }
		        }
		        return $Choices[$ChoicesList.IndexOf($Local:Selection)];
		    }
		    end {
		        Exit-Scope -ReturnValue $Local:Selection;
		        if ($Local:PreviousTabFunction -ne 'CustomAction') { Set-PSReadLineKeyHandler -Chord Tab -Function $Local:PreviousTabFunction; }
		        if ($Local:PreviousShiftTabFunction -ne 'CustomAction') { Set-PSReadLineKeyHandler -Chord Shift+Tab -Function $Local:PreviousShiftTabFunction; }
		        if ($Local:PreviousFunctions) { Unregister-CustomReadLineHandlers -PreviousHandlers $Local:PreviousFunctions; }
		    }
		}
		function Get-PopupSelection {
		    Param(
		        [Parameter()]
		        [ValidateNotNullOrEmpty()]
		        [String]$Title = 'Select a(n) Item',
		        [Parameter(Mandatory)]
		        [ValidateNotNullOrEmpty()]
		        [Object[]]$Items,
		        [Parameter()]
		        [switch]$AllowNone
		    )
		    $Local:Selection;
		    while (-not $Local:Selection) {
		        $Local:Selection = $Items | Out-GridView -Title $Title -PassThru;
		        if ((-not $AllowNone) -and (-not $Local:Selection)) {
		            Invoke-Info 'No Item was selected, re-running selection...';
		        }
		    }
		    $Local:Selection -and -not $AllowNone | Assert-NotNull -Message "Failed to select a $ItemName.";
		    return $Local:Selection;
		}
		[Boolean]$Script:CompletedSetup = $False;
		function Install-Requirements {
		    if ($Script:CompletedSetup) {
		        return;
		    }
		    Invoke-EnsureModule @{
		        Name             = 'PSReadLine';
		        MinimumVersion   = '2.3.0';
		        DontRemove       = $True;
		        RestartIfUpdated = $True;
		    };
		    $Using = [ScriptBlock]::Create('Using module ''PSReadLine''');
		    . $Using;
		    [Boolean]$Script:CompletedSetup = $True;
		}
		Export-ModuleMember -Function Get-UserInput, Get-UserConfirmation, Get-UserSelection, Get-PopupSelection -Variable Validations;
    };`
	"99-Cache" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
		[Int]$Script:FAILED_FOLDER_CREATION = Register-ExitCode 'Failed to create the cache folder.';
		[Int]$Script:FAILED_FILE_CREATION = Register-ExitCode 'Failed to create the cache file.';
		[Int]$Script:FAILED_FILE_REMOVAL = Register-ExitCode 'Failed to remove the cache file.';
		[String]$Script:Folder = [System.IO.Path]::GetTempPath() | Join-Path -ChildPath 'PSCache';
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
		            if (-not (Test-ReturnType -InputObject:$_ -ValidTypes @([Boolean]))) {
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
    };`
	"99-Connection" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
		function Local:Invoke-NonNullParams {
		    [CmdletBinding()]
		    param(
		        [Parameter(Mandatory)]
		        [String]$FunctionName,
		        [Parameter(Mandatory)]
		        [Hashtable]$Params
		    )
		    begin { Enter-Scope; }
		    end { Exit-Scope; }
		    process {
		        $Params.GetEnumerator() | Where-Object { $null -eq $_.Value } | ForEach-Object {
		            $Params.Remove($_.Key);
		        }
		        Invoke-Debug "Invoking Expression '$FunctionName $($Params.GetEnumerator() | ForEach-Object { "-$($_.Key):$($_.Value)" })'";
		        & $FunctionName @Params;
		    };
		}
		$Script:Services = @{
		    ExchangeOnline     = @{
		        Matchable  = $True;
		        Context    = { Get-ConnectionInformation | Select-Object -ExpandProperty UserPrincipalName; };
		        Connect    = { param($AccessToken) Invoke-NonNullParams 'Connect-ExchangeOnline' ($PSBoundParameters + @{ ShowBanner = $False }); };
		        Disconnect = { Disconnect-ExchangeOnline -Confirm:$False };
		    };
		    SecurityComplience = @{
		        Matchable  = $True;
		        Context    = { Get-IPPSSession | Select-Object -ExpandProperty UserPrincipalName; };
		        Connect    = { Connect-IPPSSession -ShowBanner:$False };
		        Disconnect = { Disconnect-IPPSSession };
		    };
		    AzureAD            = @{
		        Matchable  = $True;
		        Context    = { Get-AzureADCurrentSessionInfo | Select-Object -ExpandProperty Account; };
		        Connect    = { Connect-AzureAD };
		        Disconnect = { Disconnect-AzureAD };
		    };
		    Msol               = @{
		        Matchable  = $False;
		        Context    = { Get-MsolCompanyInformation | Select-Object -ExpandProperty DisplayName; };
		        Connect    = { param($AccessToken) Invoke-NonNullParams 'Connect-MsolService' @{ MsGraphAccessToken = $PSBoundParameters['AccessToken'] }; };
		        Disconnect = { Disconnect-MsolService };
		    };
		    Graph              = @{
		        Matchable  = $True;
		        Context    = { Get-MgContext | Select-Object -ExpandProperty Account; };
		        Connect    = { param($Scopes, $AccessToken)
		            if ($AccessToken) {
		                Connect-MgGraph -AccessToken:$AccessToken -NoWelcome;
		                $Local:ContextScopes = Get-MgContext | Select-Object -ExpandProperty Scopes;
		                if ($Scopes) {
		                    Invoke-Debug "Token Scopes: $($Local:ContextScopes -join ', ')";
		                    $Local:MissingScopes = $Scopes | Where-Object { $Local:ContextScopes -notcontains $_; };
		                    if ($Local:MissingScopes) {
		                        Invoke-Info "Disconnecting from Graph, missing required scope: $($Local:MissingScopes -join ', ')";
		                        Disconnect-MgGraph;
		                    }
		                }
		            }
		            if (-not (Get-MgContext)) {
		                Connect-MgGraph -Scopes:$Scopes -NoWelcome;
		            }
		        };
		        Disconnect = { Disconnect-MgGraph };
		        IsValid    = {
		            param([String[]]$Scopes)
		            $Local:Context = Get-MgContext;
		            if ($null -eq $Local:Context) {
		                return $False;
		            }
		            if ($Scopes) {
		                Invoke-Debug 'Checking if connected to Graph with required scopes...';
		                Invoke-Debug "Required Scopes: $($Scopes -join ', ')";
		                Invoke-Debug "Current Scopes: $($Local:Context.Scopes -join ', ')";
		                [Bool]$Local:HasAllScopes = ($Scopes | Where-Object { $Local:Context.Scopes -notcontains $_; }).Count -eq 0;
		            }
		            else {
		                $Local:HasAllScopes = $True;
		            }
		            $Local:HasAllScopes;
		        }
		    };
		}
		[Int]$Script:ERROR_CANT_DISCONNECT = Register-ExitCode -Description 'Failed to disconnect from {0}.';
		function Local:Disconnect-ServiceInternal {
		    [CmdletBinding(SupportsShouldProcess)]
		    param(
		        [Parameter(Mandatory)]
		        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'AzureAD', 'Graph', 'Msol')]
		        [String]$Service
		    )
		    begin { Enter-Scope; }
		    end { Exit-Scope; }
		    process {
		        Invoke-Info "Disconnecting from $Local:Service...";
		        try {
		            if ($PSCmdlet.ShouldProcess("Disconnect from $Local:Service")) {
		                & $Script:Services[$Local:Service].Disconnect | Out-Null;
		            };
		        }
		        catch {
		            Invoke-FailedExit -ExitCode $Script:ERROR_CANT_DISCONNECT -FormatArgs @($Local:Service) -ErrorRecord $_;
		        }
		    }
		}
		function Local:Connect-ServiceInternal {
		    [CmdletBinding(SupportsShouldProcess)]
		    param(
		        [Parameter(Mandatory)]
		        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'AzureAD', 'Graph', 'Msol')]
		        [String]$Service,
		        [Parameter()]
		        [String[]]$Scopes,
		        [Parameter()]
		        [SecureString]$AccessToken
		    )
		    begin { Enter-Scope; }
		    end { Exit-Scope; }
		    process {
		        Invoke-Info "Connecting to $Local:Service...";
		        Invoke-Verbose "Scopes: $($Scopes -join ', ')";
		        try {
		            if ($PSCmdlet.ShouldProcess("Connect to $Local:Service")) {
		                $null = & $Script:Services[$Local:Service].Connect -Scopes:$Scopes -AccessToken:$AccessToken;
		            }
		        }
		        catch {
		            Invoke-FailedExit -ExitCode $Script:ERROR_COULDNT_CONNECT -FormatArgs @($Local:Service) -ErrorRecord $_;
		        }
		    }
		}
		function Local:Get-ServiceContext {
		    [CmdletBinding()]
		    param(
		        [Parameter(Mandatory)]
		        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'AzureAD', 'Graph', 'Msol')]
		        [String]$Service
		    )
		    try {
		        & $Script:Services[$Service].Context;
		    }
		    catch {
		        $null;
		    }
		}
		function Local:Test-HasContext {
		    [CmdletBinding()]
		    param(
		        [Parameter(Mandatory)]
		        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'AzureAD', 'Graph', 'Msol')]
		        [String]$Service
		    )
		    $null -ne (Get-ServiceContext -Service $Service);
		}
		function Local:Test-IsMatchable {
		    [CmdletBinding()]
		    param(
		        [Parameter(Mandatory)]
		        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'AzureAD', 'Graph', 'Msol')]
		        [String]$ServiceA,
		        [Parameter()]
		        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'AzureAD', 'Graph', 'Msol')]
		        [String]$ServiceB
		    )
		    $Script:Services[$Service].Matchable -and (-not $ServiceB -or $Script:Services[$ServiceB].Matchable);
		}
		function Local:Test-SameContext {
		    [CmdletBinding()]
		    param(
		        [Parameter(Mandatory)]
		        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'AzureAD', 'Graph', 'Msol')]
		        [String]$ServiceA,
		        [Parameter(Mandatory)]
		        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'AzureAD', 'Graph', 'Msol')]
		        [String]$ServiceB
		    )
		    [String]$Private:ContextA = Get-ServiceContext -Service $ServiceA;
		    [String]$Private:ContextB = Get-ServiceContext -Service $ServiceB;
		    $Private:ContextA -and $Private:ContextB -and ($Private:ContextA -eq $Private:ContextB);
		}
		function Local:Test-NotMatchableOrSameContext {
		    [CmdletBinding()]
		    param(
		        [Parameter(Mandatory)]
		        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'AzureAD', 'Graph', 'Msol')]
		        [String]$ServiceA,
		        [Parameter(Mandatory)]
		        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'AzureAD', 'Graph', 'Msol')]
		        [String]$ServiceB
		    )
		    (Test-IsMatchable -ServiceA $ServiceA -ServiceB $ServiceB) -or (Test-SameContext -ServiceA $ServiceA -ServiceB $ServiceB);
		}
		[Int]$Script:ERROR_NOT_CONNECTED = Register-ExitCode -Description 'Not connected to {0}, must be connected to continue.';
		[Int]$Script:ERROR_COULDNT_CONNECT = Register-ExitCode -Description 'Failed to connect to {0}.';
		[Int]$Script:ERROR_NOT_MATCHING_ACCOUNTS = Register-ExitCode -Description 'Not all services are connected with the same account, please ensure all services are connected with the same account.';
		function Connect-Service(
		    [Parameter(Mandatory)]
		    [ValidateSet('ExchangeOnline', 'SecurityComplience', 'AzureAD', 'Graph', 'Msol')]
		    [String[]]$Services,
		    [Parameter()]
		    [String[]]$Scopes,
		    [Parameter()]
		    [SecureString]$AccessToken,
		    [Switch]$DontConfirm,
		    [Switch]$CheckOnly
		) {
		    begin { Enter-Scope; }
		    end { Exit-Scope; }
		    process {
		        [String]$Local:LastService;
		        [String]$Local:Account;
		        foreach ($Local:Service in $Services) {
		            [String]$Local:Context = try {
		                Get-ServiceContext -Service $Local:Service;
		            }
		            catch {
		                Invoke-Debug "Failed to get connection information for $Local:Service";
		                if ($Global:Logging.Debug) {
		                    Format-Error -InvocationInfo $_.InvocationInfo;
		                }
		            }
		            if ($Local:LastService -and (Test-NotMatchableOrSameContext -ServiceA:$Local:Service -ServiceB:$Local:LastService)) {
		                Invoke-Info 'Not all services are connected with the same account, forcing disconnect...';
		                Disconnect-ServiceInternal -Service:$Local:Service;
		            }
		            elseif ($Local:Context) {
		                [ScriptBlock]$Local:ValidCheck = $Script:Services[$Local:Service].IsValid;
		                if ($Local:ValidCheck -and -not (& $Local:ValidCheck -Scopes:$Scopes)) {
		                    Invoke-Info "Connected to $Local:Service, but missing required scopes. Disconnecting...";
		                    Disconnect-ServiceInternal -Service $Local:Service;
		                }
		                elseif (!$DontConfirm) {
		                    $Local:Continue = Get-UserConfirmation -Title "Already connected to $Local:Service as [$Local:Context]" -Question 'Do you want to continue?' -DefaultChoice $true;
		                    if ($Local:Continue) {
		                        Invoke-Verbose 'Continuing with current connection...';
		                        $Local:Account = $Local:Context;
		                        $Local:LastService = $Local:Service;
		                        continue;
		                    }
		                    Disconnect-ServiceInternal -Service $Local:Service;
		                }
		                else {
		                    Invoke-Verbose "Already connected to $Local:Service. Skipping...";
		                    $Local:Account = $Local:Context;
		                    $Local:LastService = $Local:Service;
		                    continue
		                }
		            }
		            elseif ($CheckOnly) {
		                Invoke-FailedExit -ExitCode:$Script:ERROR_NOT_CONNECTED -FormatArgs @($Local:Service) -ErrorRecord $_;
		            }
		            while ($True) {
		                try {
		                    if ($AccessToken) { Invoke-Info "Connecting to $Local:Service with access token..."; }
		                    else { Invoke-Info "Connecting to $Local:Service..."; }
		                    Connect-ServiceInternal -Service:$Local:Service -Scopes:$Scopes -AccessToken:$AccessToken;
		                }
		                catch {
		                    Invoke-FailedExit -ExitCode $Script:ERROR_COULDNT_CONNECT -FormatArgs @($Local:Service) -ErrorRecord $_;
		                }
		                if ($Local:Account -and (Test-NotMatchableOrSameContext -ServiceA:$Local:Service -ServiceB:$Local:LastService)) {
		                    Invoke-Warn 'Not all services are connected with the same account, please reconnect with the same account.';
		                    Disconnect-ServiceInternal -Service $Local:Service;
		                    continue;
		                }
		                if (-not $Local:Account -and (Test-IsMatchable $Local:Service)) {
		                    $Local:Account = Get-ServiceContext -Service $Local:Service;
		                }
		                Invoke-Info "Connected to $Local:Service as [$Local:Account].";
		                break;
		            };
		        }
		    }
		}
		Export-ModuleMember -Function Connect-Service;
    };`
	"99-Flag" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
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
		            Write-Warning -Message "Data is ignored for RunningFlag, only the PID of the running process is stored."
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
		        [DateTime]$Local:RebootFlagTime = (Get-Item $this.FlagPath).LastWriteTime;
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
    };`
	"99-Registry" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
		function Invoke-EnsureRegistryPath {
		    [CmdletBinding(SupportsShouldProcess)]
		    param (
		        [Parameter(Mandatory)]
		        [ValidateSet('HKLM', 'HKCU')]
		        [String]$Root,
		        [Parameter(Mandatory)]
		        [ValidateNotNull()]
		        [String]$Path
		    )
		    begin { Enter-Scope; }
		    end { Exit-Scope; }
		    process {
		        [String[]]$Local:PathParts = $Path.Split('\') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) };
		        [String]$Local:CurrentPath = "${Root}:";
		        foreach ($Local:PathPart in $Local:PathParts) {
		            [String]$Local:CurrentPath = Join-Path -Path $Local:CurrentPath -ChildPath $Local:PathPart;
		            if (Test-Path -Path $Local:CurrentPath -PathType Container) {
		                Invoke-Verbose "Registry key '$Local:CurrentPath' already exists.";
		                continue;
		            }
		            if ($PSCmdlet.ShouldProcess($Local:CurrentPath, 'Create')) {
		                Invoke-Verbose "Creating registry key '$Local:CurrentPath'...";
		                $null = New-Item -Path $Local:CurrentPath -Force -ItemType RegistryKey;
		            }
		        }
		    }
		}
		function Test-RegistryKey {
		    [CmdletBinding()]
		    param (
		        [Parameter(Mandatory)]
		        [String]$Path,
		        [Parameter(Mandatory)]
		        [String]$Key
		    )
		    begin { Enter-Scope; }
		    end { Exit-Scope; }
		    process {
		        if (Test-Path -Path $Path -PathType Container) {
		            if (Get-ItemProperty -Path $Path -Name $Key -ErrorAction SilentlyContinue) {
		                return $True;
		            }
		        }
		        return $False;
		    }
		}
		function Get-RegistryKey {
		    [CmdletBinding()]
		    param (
		        [Parameter(Mandatory)]
		        [String]$Path,
		        [Parameter(Mandatory)]
		        [String]$Key
		    )
		    begin { Enter-Scope; }
		    end { Exit-Scope; }
		    process {
		        if (Test-RegistryKey -Path $Path -Key $Key) {
		            return Get-ItemProperty -Path $Path -Name $Key;
		        }
		        return $Null;
		    }
		}
		function Set-RegistryKey {
		    [CmdletBinding(SupportsShouldProcess)]
		    param (
		        [Parameter(Mandatory)]
		        [String]$Path,
		        [Parameter(Mandatory)]
		        [String]$Key,
		        [Parameter(Mandatory)]
		        [String]$Value,
		        [Parameter(Mandatory)]
		        [ValidateSet('Binary', 'DWord', 'ExpandString', 'MultiString', 'None', 'QWord', 'String')]
		        [Microsoft.Win32.RegistryValueKind]$Kind
		    )
		    begin { Enter-Scope; }
		    end { Exit-Scope; }
		    process {
		        Invoke-EnsureRegistryPath -Root $Path.Substring(0, 4) -Path $Path.Substring(5);
		        if ($PSCmdlet.ShouldProcess($Path, 'Set')) {
		            Invoke-Verbose "Setting registry key '$Path' to '$Value'...";
		            Set-ItemProperty -Path $Path -Name $Key -Value $Value -Type $Kind;
		        }
		    }
		}
		function Remove-RegistryKey {
		    [CmdletBinding(SupportsShouldProcess)]
		    param (
		        [Parameter(Mandatory)]
		        [String]$Path,
		        [Parameter(Mandatory)]
		        [String]$Key
		    )
		    begin { Enter-Scope; }
		    end { Exit-Scope; }
		    process {
		        if (-not (Test-RegistryKey -Path $Path -Key $Key)) {
		            Invoke-Verbose "Registry key '$Path\$Key' does not exist.";
		            return;
		        }
		        if ($PSCmdlet.ShouldProcess($Path, 'Remove')) {
		            Invoke-Verbose "Removing registry key '$Path\$Key'...";
		            Remove-ItemProperty -Path $Path -Name $Key;
		        }
		    }
		}
		function Get-AllSIDs {
		    $PatternSID = '(?:S-1-5-21|S-1-12-1)-\d+-\d+\-\d+\-\d+$'
		    Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*' `
		    | Where-Object { $_.PSChildName -match $PatternSID } `
		    | Select-Object @{name = 'SID'; expression = { $_.PSChildName } },
		    @{name = 'UserHive'; expression = { "$($_.ProfileImagePath)\ntuser.dat" } },
		    @{name = 'Username'; expression = { $_.ProfileImagePath -replace '^(.*[\\\/])', '' } } `
		    | Where-Object { Test-Path -Path $_.UserHive };
		}
		function Get-UnloadedUserHives {
		    param(
		        [Parameter(Mandatory)]
		        [PSCustomObject[]]$LoadedHives,
		        [Parameter(Mandatory)]
		        [PSCustomObject[]]$ProfileList
		    )
		    Compare-Object $ProfileList.SID $LoadedHives.SID | Select-Object @{name = 'SID'; expression = { $_.InputObject } }, UserHive, Username
		}
		function Get-LoadedUserHives {
		    return Get-ChildItem Registry::HKEY_USERS `
		    | Where-Object { $_.PSChildname -match $PatternSID } `
		    | Select-Object @{name = 'SID'; expression = { $_.PSChildName } };
		}
		function Invoke-OnEachUserHive {
		    [CmdletBinding()]
		    param (
		        [Parameter(Mandatory)]
		        [ScriptBlock]$ScriptBlock
		    )
		    begin { Enter-Scope; }
		    end { Exit-Scope; }
		    process {
		        [PSCustomObject[]]$Private:ProfileList = Get-AllSIDs;
		        [PSCustomObject[]]$Private:LoadedHives = Get-LoadedUserHives;
		        [PSCustomObject[]]$Private:UnloadedHives = Get-UnloadedUserHives -LoadedHives $Private:LoadedHives -ProfileList $Private:ProfileList;
		        Invoke-Debug "Loaded hives: $($Private:LoadedHives.SID -join ', ')";
		        Invoke-Debug "Unloaded hives: $($Private:UnloadedHives.SID -join ', ')";
		        Foreach ($Private:Hive in $Private:ProfileList) {
		            Invoke-Verbose "Processing hive '$($Private:Hive)'...";
		            $Private:IsUnloadedHive = $Private:Hive.SID -in $Private:UnloadedHives.SID;
		            If ($Private:IsUnloadedHive) {
		                Invoke-Debug "Loading hive '$($Private:Hive.UserHive)'...";
		                reg load "HKU\$($Private:Hive.SID)" $Private:Hive.UserHive;
		                if (-not (Test-Path -Path Registry::HKEY_USERS\$($Private:Hive.SID))) {
		                    Invoke-Warn "Failed to load hive '$($Private:Hive.UserHive)'.";
		                    continue;
		                }
		            }
		            try {
		                Invoke-Debug 'Executing script block...';
		                & $ScriptBlock -Hive $Private:Hive;
		            }
		            finally {
		                If ($Private:IsUnloadedHive) {
		                    Invoke-Debug "Unloading hive '$($Private:Hive.UserHive)'...";
		                    [GC]::Collect();
		                    reg unload HKU\$($Private:Hive.SID);
		                }
		            }
		        }
		    }
		}
		Export-ModuleMember -Function New-RegistryKey, Remove-RegistryKey, Test-RegistryKey, Get-RegistryKey, Set-RegistryKey, Invoke-OnEachUserHive;
    };`
	"99-UsersAndAccounts" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
		$Script:InitialisedAllGroups = $False;
		$Script:CachedGroups = @{};
		$Script:InitialisedAllUsers = $False;
		$Script:CachedUsers = @{};
		function Local:Get-ObjectByInputOrName(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [ValidateScript({ $_ -is [String] -or $_ -is [ADSI] })]
		    [Object]$InputObject,
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [String]$SchemaClassName,
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [ScriptBlock]$GetByName
		) {
		    begin {
		        Enter-Scope -ArgumentFormatter @{
		            InputObject = { "$($_.Name) of type $($_.SchemaClassName)" };
		        };
		    }
		    end { Exit-Scope -ReturnValue $Local:Value; }
		    process {
		        if ($InputObject -is [String] -and $InputObject -eq '') {
		            Write-Error 'An empty string was supplied, this is not a valid object.' -Category InvalidArgument;
		        }
		        if ($InputObject -is [String]) {
		            [ADSI]$Local:Value = $GetByName.InvokeReturnAsIs();
		        }
		        elseif ($InputObject.SchemaClassName -ne $SchemaClassName) {
		            Write-Host "$($InputObject.SchemaClassName)"
		            Write-Error "The supplied object is not a $SchemaClassName." -TargetObject $InputObject -Category InvalidArgument;
		        }
		        else {
		            [ADSI]$Local:Value = $InputObject;
		        }
		        return $Local:Value;
		    }
		}
		function Get-GroupByInputOrName([Object]$InputObject) {
		    return Get-ObjectByInputOrName -InputObject $InputObject -SchemaClassName 'Group' -GetByName { Get-Group $InputObject; };
		}
		function Get-UserByInputOrName([Object]$InputObject) {
		    return Get-ObjectByInputOrName -InputObject $InputObject -SchemaClassName 'User' -GetByName {
		        if (-not ($InputObject.Contains('/'))) {
		            $InputObject = "$env:COMPUTERNAME/$InputObject";
		        }
		        Get-User $InputObject;
		    };
		}
		function Get-Group(
		    [Parameter(HelpMessage = 'The name of the group to retrieve, if not specified all groups will be returned.')]
		    [ValidateNotNullOrEmpty()]
		    [String]$Name
		) {
		    begin { Enter-Scope; }
		    end { Exit-Scope -ReturnValue $Local:Value; }
		    process {
		        if (-not $Name) {
		            Invoke-Debug 'Getting all groups...'
		            if (-not $Script:InitialisedAllGroups) {
		                Invoke-Debug 'Initialising all groups...';
		                $Script:CachedGroups;
		                [ADSI]$Local:Groups = [ADSI]"WinNT://$env:COMPUTERNAME";
		                $Local:Groups.Children | Where-Object { $_.SchemaClassName -eq 'Group' } | ForEach-Object { $Script:CachedGroups[$_.Name] = $_; };
		                $Script:InitialisedAllGroups = $True;
		            }
		            $Local:Value = $Script:CachedGroups.Values;
		        }
		        else {
		            Invoke-Debug "Getting group $Name...";
		            if (-not $Script:InitialisedAllGroups -or -not $Script:CachedGroups[$Name]) {
		                [ADSI]$Local:Group = [ADSI]"WinNT://$env:COMPUTERNAME/$Name,group";
		                $Script:CachedGroups[$Name] = $Local:Group;
		            }
		            $Local:Value = $Script:CachedGroups[$Name];
		        }
		        return $Local:Value;
		    }
		}
		function Get-MembersOfGroup(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [Object]$Group
		) {
		    begin { Enter-Scope; }
		    end { Exit-Scope -ReturnValue $Local:Members; }
		    process {
		        [ADSI]$Local:Group = Get-GroupByInputOrName -InputObject:$Group;
		        $Group.Invoke('Members') `
		        | ForEach-Object { [ADSI]$_ } `
		        | Where-Object {
		            if ($_.Parent.Length -gt 8) {
		                $_.Parent.Substring(8) -ne 'NT AUTHORITY'
		            }
		            else {
		                $False
		            }
		        };
		    }
		}
		function Test-MemberOfGroup(
		    [Parameter(Mandatory)]
		    [Object]$Group,
		    [Parameter(Mandatory)]
		    [Object]$User
		) {
		    begin {
		        Enter-Scope -ArgumentFormatter @{
		            Group = { $_.Name + $_.SchemaClassName };
		            User  = { $_.Name + $_.SchemaClassName };
		        };
		    }
		    end { Exit-Scope -ReturnValue $Local:User; }
		    process {
		        Invoke-Debug 'Getting group';
		        [ADSI]$Local:Group = Get-GroupByInputOrName -InputObject $Group;
		        Invoke-Debug 'Getting user';
		        [ADSI]$Local:User = Get-UserByInputOrName -InputObject $User;
		        Invoke-Debug 'Testing if user is a member of group...';
		        return $Local:Group.Invoke('IsMember', $Local:User.Path);
		    }
		}
		function Add-MemberToGroup(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [Object]$Group,
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [Object]$User
		) {
		    begin { Enter-Scope; }
		    end { Exit-Scope; }
		    process {
		        [ADSI]$Local:Group = Get-GroupByInputOrName -InputObject $Group;
		        [ADSI]$Local:User = Get-UserByInputOrName -InputObject $User;
		        if (Test-MemberOfGroup -Group $Local:Group -User $Local:User) {
		            Invoke-Verbose "User $User is already a member of group $Group.";
		            return $False;
		        }
		        Invoke-Verbose "Adding user $Name to group $Group...";
		        $Local:Group.Invoke('Add', $Local:User.Path);
		        return $True;
		    }
		}
		function Remove-MemberFromGroup(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [Object]$Group,
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [Object]$Member
		) {
		    begin { Enter-Scope; }
		    end { Exit-Scope; }
		    process {
		        [ADSI]$Local:Group = Get-GroupByInputOrName -InputObject $Group;
		        [ADSI]$Local:User = Get-UserByInputOrName -InputObject $Member;
		        if (-not (Test-MemberOfGroup -Group $Local:Group -User $Local:User)) {
		            Invoke-Verbose "User $Member is not a member of group $Group.";
		            return $False;
		        }
		        Invoke-Verbose "Removing user $Name from group $Group...";
		        $Local:Group.Invoke('Remove', $Local:User.Path);
		        return $True;
		    }
		}
		function Get-User(
		    [Parameter(HelpMessage = 'The name of the user to retrieve, if not specified all users will be returned.')]
		    [ValidateNotNullOrEmpty()]
		    [String]$Name
		) {
		    begin { Enter-Scope; }
		    process {
		        if (-not $Name) {
		            if (-not $Script:InitialisedAllUsers) {
		                $Script:CachedUsers = @{};
		                [ADSI]$Local:Users = [ADSI]"WinNT://$env:COMPUTERNAME";
		                $Local:Users.Children | Where-Object { $_.SchemaClassName -eq 'User' } | ForEach-Object { $Script:CachedUsers[$_.Name] = $_; };
		                $Script:InitialisedAllUsers = $True;
		            }
		            $Local:Value = $Script:CachedUsers;
		        }
		        else {
		            $null = Get-User;
		            if (-not $Script:InitialisedAllUsers -or -not $Script:CachedUsers[$Name]) {
		                $Script:CachedUsers = @{};
		                [ADSI]$Local:User = [ADSI]"WinNT://$Name,user";
		                $Script:CachedUsers[$Name] = $Local:User;
		            }
		            $Local:Value = $Script:CachedUsers[$Name];
		            $Global:CachedUsers = $Script:CachedUsers;
		        }
		        return $Local:Value;
		    }
		}
		function Get-UserGroups(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [Object]$User
		) {
		    begin { Enter-Scope; }
		    end { Exit-Scope -ReturnValue $Local:UserGroups; }
		    process {
		        [ADSI]$Local:User = Get-UserByInputOrName -InputObject $User;
		        [String]$Local:Domain = $Local:User.Path.Split('/')[0];
		        [String]$Local:Username = $Local:User.Path.Split('/')[1];
		        Get-WmiObject -Class Win32_GroupUser `
		        | Where-Object { $_.PartComponent -match "Domain=""$Domain"",Name=""$Username""" } `
		        | ForEach-Object { [WMI]$_.GroupComponent };
		        return $Local:UserGroups;
		    }
		}
		function Format-ADSIUser(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [ValidateScript({ $_ | ForEach-Object { $_.SchemaClassName -eq 'User' } })]
		    [ADSI[]]$User
		) {
		    begin { Enter-Scope; }
		    end { Exit-Scope -ReturnValue $Local:Value; }
		    process {
		        if ($User -is [Array] -and $User.Count -gt 1) {
		            $Local:Value = $User | ForEach-Object {
		                Format-ADSIUser -User $_;
		            };
		            return $Local:Value;
		        }
		        else {
		            [String]$Local:Path = $User.Path.Substring(8); # Remove the WinNT:// prefix
		            [String[]]$Local:PathParts = $Local:Path.Split('/');
		            [HashTable]$Local:Value = @{
		                Name   = $Local:PathParts[$Local:PathParts.Count - 1]
		                Domain = $Local:PathParts[$Local:PathParts.Count - 2]
		            };
		            return $Local:Value;
		        }
		    }
		}
		Export-ModuleMember -Function Get-User, Get-UserGroups, Get-Group, Get-MembersOfGroup, Test-MemberOfGroup, Add-MemberToGroup, Remove-MemberFromGroup, Format-ADSIUser, Get-GroupByInputOrName, Get-UserByInputOrName;
    };
}

(New-Module -ScriptBlock $Global:EmbededModules['00-Environment'] -AsCustomObject -ArgumentList $MyInvocation.BoundParameters).'Invoke-RunMain'($PSCmdlet, {
    try {
        & $Expression;
    } catch {
        Invoke-FailedExit -ExitCode 1001 -ErrorRecord $_;
    }
});
