#Requires -Modules Microsoft.Graph.Authentication Microsoft.Graph.Beta.DeviceManagement Microsoft.Graph.Beta.Groups
#Requires -Version 5.1


$Global:CompiledScript = $true;
$Global:EmbededModules = [ordered]@{
    "00-Environment" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
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
		        } else {
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
		        } else {
		            return $false;
		        }
		    }
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
		        Invoke-EnvDebug -Message "Importing module $Name.";
		        if ($Value -is [ScriptBlock]) {
		            Invoke-EnvDebug -Message "Module $Name is a script block.";
		            if (Get-Module -Name $Name) {
		                Remove-Module -Name $Name -Force;
		            }
		            New-Module -ScriptBlock $Value -Name $Name | Import-Module -Global -Force;
		        } else {
		            Invoke-EnvDebug -Message "Module $Name is a file or installed module.";
		            Import-Module -Name $Value -Global -Force;
		        }
		    }
		    # Collect a List of the modules to import.
		    if ($Global:CompiledScript) {
		        Invoke-EnvVerbose 'Script has been embeded with required modules.';
		        [HashTable]$Local:ToImport = $Global:EmbededModules;
		    } elseif (Test-Path -Path "$($MyInvocation.MyCommand.Module.Path | Split-Path -Parent)/../../.git") {
		        Invoke-EnvVerbose 'Script is in git repository; Using local files.';
		        [HashTable]$Local:ToImport = Get-FilsAsHashTable -Path "$($MyInvocation.MyCommand.Module.Path | Split-Path -Parent)/*.psm1";
		    } else {
		        [String]$Local:RepoPath = "$($env:TEMP)/AMTScripts";
		        if (Get-Command -Name 'git' -ErrorAction SilentlyContinue) {
		            if (-not (Test-Path -Path $Local:RepoPath)) {
		                Invoke-EnvVerbose -UnicodePrefix '♻️' -Message 'Cloning repository.';
		                git clone https://github.com/AMTSupport/scripts.git $Local:RepoPath;
		            } else {
		                Invoke-EnvVerbose -UnicodePrefix '♻️' -Message 'Updating repository.';
		                git -C $Local:RepoPath pull;
		            }
		        } else {
		            Invoke-EnvInfo -Message 'Git is not installed, unable to update the repository or clone if required.';
		        }
		        [HashTable]$Local:ToImport = Get-FilsAsHashTable -Path "$Local:RepoPath/src/common/*.psm1";
		    }
		    # Import PSStyle Before anything else.
		    Import-ModuleOrScriptBlock -Name:'00-PSStyle' -Value:$Local:ToImport['00-PSStyle'];
		    # Import the modules.
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
		        Invoke-EnvDebug -Message "Removing module $_.";
		        if ($_ -eq '01-Logging') {
		            $Global:Logging.Loaded = $false;
		        }
		        Remove-Module -Name $_ -Force;
		    };
		    if ($Global:CompiledScript) {
		        Remove-Variable -Scope Global -Name CompiledScript, EmbededModules, Logging;
		    }
		}
		function Invoke-RunMain {
		    Param(
		        [Parameter(Mandatory)]
		        [ValidateNotNull()]
		        [System.Management.Automation.InvocationInfo]$Invocation,
		        [Parameter(Mandatory)]
		        [ValidateNotNull()]
		        [ScriptBlock]$Main,
		        [Parameter(DontShow)]
		        [Switch]$DontImport,
		        [Parameter(DontShow)]
		        [Switch]$HideDisclaimer = (($Host.UI.RawUI.WindowTitle | Split-Path -Leaf) -eq 'fmplugin.exe')
		    )
		    # Workaround for embedding modules in a script, can't use Invoke if a scriptblock contains begin/process/clean blocks
		    function Invoke-Inner {
		        Param(
		            [Parameter(Mandatory)]
		            [ValidateNotNull()]
		            [System.Management.Automation.InvocationInfo]$Invocation,
		            [Parameter(Mandatory)]
		            [ValidateNotNull()]
		            [ScriptBlock]$Main,
		            [Parameter(DontShow)]
		            [Switch]$DontImport,
		            [Parameter(DontShow)]
		            [Switch]$HideDisclaimer
		        )
		        begin {
		            foreach ($Local:Param in @('Verbose','Debug')) {
		                if ($Invocation.BoundParameters.ContainsKey($Local:Param)) {
		                    $Global:Logging[$Local:Param] = $Invocation.BoundParameters[$Local:Param];
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
		        }
		        process {
		            try {
		                # TODO :: Fix this, it's not working as expected
		                # If the script is being run directly, invoke the main function
		                # If ($Invocation.CommandOrigin -eq 'Runspace') {
		                Invoke-EnvVerbose -UnicodePrefix '🚀' -Message 'Running main function.';
		                & $Main;
		            } catch {
		                if ($_.FullyQualifiedErrorId -eq 'QuickExit') {
		                    Invoke-EnvVerbose -UnicodePrefix '✅' -Message 'Main function finished successfully.';
		                } elseif ($_.FullyQualifiedErrorId -eq 'FailedExit') {
		                    [Int16]$Local:ExitCode = $_.TargetObject;
		                    Invoke-EnvVerbose -Message "Script exited with an error code of $Local:ExitCode.";
		                    $LASTEXITCODE = $Local:ExitCode;
		                } else {
		                    Invoke-Error 'Uncaught Exception during script execution';
		                    Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_ -DontExit;
		                }
		            } finally {
		                Invoke-Handlers;
		                if (-not $Local:DontImport) {
		                    Remove-CommonModules;
		                }
		            }
		        }
		    }
		    Invoke-Inner `
		        -Invocation $Invocation `
		        -Main $Main `
		        -DontImport:$DontImport `
		        -HideDisclaimer:($HideDisclaimer -or $False) `
		        -Verbose:(Get-OrFalse $Invocation.BoundParameters 'Verbose') `
		        -Debug:(Get-OrFalse $Invocation.BoundParameters 'Debug');
		}
		Export-ModuleMember -Function Invoke-RunMain, Import-CommonModules, Remove-CommonModules;
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
		                } else {
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
		function Test-ReturnType {
		    [CmdletBinding()]
		    param(
		        [Parameter(Mandatory, HelpMessage = 'The AST object to test.')]
		        [ValidateNotNullOrEmpty()]
		        [Object]$InputObject,
		        [Parameter(Mandatory, HelpMessage = 'The Valid Types to test against.')]
		        [ValidateNotNullOrEmpty()]
		        [String[]]$ValidTypes,
		        [Parameter(HelpMessage = 'Allow the return type to be null.')]
		        [Switch]$AllowNull
		    )
		    process {
		        $Local:Ast = Get-Ast -InputObject $InputObject;
		        $Local:AllReturnStatements = $Local:Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ReturnStatementAst] }, $true);
		        foreach ($Local:ReturnStatement in $Local:AllReturnStatements) {
		            [System.Management.Automation.Language.ExpressionAst]$Local:Expression = $Local:ReturnStatement.Pipeline.PipelineElements[0].expression;
		            # TODO - Better handling of the variable path.
		            if ($Local:Expression.VariablePath) {
		                [String]$Local:VariableName = $Local:Expression.VariablePath.UserPath;
		                # Try to resolve the variable and check its type.
		                $Local:Variable = Get-Variable -Name:$Local:VariableName -ValueOnly -ErrorAction SilentlyContinue;
		                if ($Local:Variable) {
		                    [System.Reflection.TypeInfo]$Local:ReturnType = $Local:Variable.GetType();
		                    [String]$Local:TypeName = $Local:ReturnType.Name;
		                    if ($ValidTypes -contains $Local:TypeName) {
		                        continue;
		                    }
		                } else {
		                    Invoke-Debug -Message "Could not resolve the variable: $Local:VariableName.";
		                    continue
		                }
		            } else {
		                [System.Reflection.TypeInfo]$Local:ReturnType = $Local:Expression.StaticType;
		                [String]$Local:TypeName = $Local:ReturnType.Name;
		                Invoke-Debug "Return type: $Local:TypeName";
		                if ($ValidTypes -contains $Local:TypeName -or ($AllowNull -and $Local:Expression.Extent.Text -eq '$null' -and $Local:ReturnType.Name -eq 'Object')) {
		                    continue;
		                }
		            }
		            $Local:Region = $Local:Expression.Extent;
		            Invoke-Warn -Message "
		            The return type of the script block is not valid. Expected: $($ValidTypes -join ', '); Actual: $Local:TypeName.
		            At: $($Local:Region.StartLineNumber):$($Local:Region.StartColumnNumber) - $($Local:Region.EndLineNumber):$($Local:Region.EndColumnNumber)
		            Text: $($Local:Region.Text)
		            ";
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
    };`
	"01-Logging" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
        function Test-NAbleEnvironment {
		    [String]$Local:ConsoleTitle = [Console]::Title | Split-Path -Leaf;
		    $Local:ConsoleTitle -eq 'fmplugin.exe';
		}
		function Get-SupportsUnicode {
		    $null -ne $env:WT_SESSION -and -not (Test-NAbleEnvironment);
		}
		function Get-SupportsColour {
		    $Host.UI.SupportsVirtualTerminal -and -not (Test-NAbleEnvironment);
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
		        [Boolean]$ShouldWrite
		    )
		    process {
		        if ($InputObject) {
		            Invoke-Write @InputObject;
		            return;
		        }
		        if (-not $ShouldWrite) {
		            return;
		        }
		        [String]$Local:NewLineTab = if ($PSPrefix -and (Get-SupportsUnicode)) {
		            "$(' ' * $($PSPrefix.Length))";
		        } else { ''; }
		        [String]$Local:FormattedMessage = if ($PSMessage.Contains("`n")) {
		            $PSMessage -replace "`n", "`n$Local:NewLineTab+ ";
		        } else { $PSMessage; }
		        if (Get-SupportsColour) {
		            $Local:FormattedMessage = "$(Get-ConsoleColour $PSColour)$Local:FormattedMessage$($PSStyle.Reset)";
		        }
		        [String]$Local:FormattedMessage = if ($PSPrefix -and (Get-SupportsUnicode)) {
		            "$PSPrefix $Local:FormattedMessage";
		        } else { $Local:FormattedMessage; }
		        $InformationPreference = 'Continue';
		        Write-Information $Local:FormattedMessage;
		    }
		}
		function Invoke-FormattedError(
		    [Parameter(Mandatory, HelpMessage = 'The error records invocation info.')]
		    [ValidateNotNullOrEmpty()]
		    [System.Management.Automation.InvocationInfo]$InvocationInfo,
		    [Parameter(HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
		    [ValidateNotNullOrEmpty()]
		    [String]$Message,
		    [Parameter(HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
		    [ValidateNotNullOrEmpty()]
		    [Alias('Prefix')]
		    [String]$UnicodePrefix
		) {
		    [String]$Local:TrimmedLine = $InvocationInfo.Line.Trim();
		    [String]$Local:Script = $InvocationInfo.ScriptName.Trim();
		    if ($InvocationInfo.Statement) {
		        [String]$Local:Statement = $InvocationInfo.Statement.Trim();
		        # Find where the statement matches in the line, and underline it, indent the statement to where it matches in the line.
		        [Int]$Local:StatementIndex = $Local:TrimmedLine.IndexOf($Local:Statement);
		        # FIXME: This is a hack to fix the issue where the statement index is -1, this shouldn't happen!
		        if ($Local:StatementIndex -lt 0) {
		            [Int]$Local:StatementIndex = 0;
		        }
		    } else {
		        [Int]$Local:StatementIndex = 0;
		        [String]$Local:Statement = $TrimmedLine;
		    }
		    [String]$Local:Underline = (' ' * ($Local:StatementIndex + 10)) + ('^' * $Local:Statement.Length);
		    # Position the message to the same indent as the statement.
		    [String]$Local:Message = if ($null -ne $Message) {
		        (' ' * $Local:StatementIndex) + $Message;
		    } else { $null };
		    # Fucking PS 5 doesn't allow variable overrides so i have to add the colour to all of them. :<(
		    [HashTable]$Local:BaseHash = @{
		        PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { $null };
		        ShouldWrite = $True;
		    };
		    Invoke-Write @Local:BaseHash -PSMessage "File    | $($PSStyle.Foreground.Red)$Local:Script" -PSColour Cyan;
		    Invoke-Write @Local:BaseHash -PSMessage "Line    | $($PSStyle.Foreground.Red)$($InvocationInfo.ScriptLineNumber)" -PSColour Cyan;
		    Invoke-Write @Local:BaseHash -PSMessage "Preview | $($PSStyle.Foreground.Red)$Local:TrimmedLine" -PSColour Cyan;
		    Invoke-Write @Local:BaseHash -PSMessage "$Local:Underline" -PSColour 'Red';
		    if ($Local:Message) {
		        Invoke-Write @Local:BaseHash -PSMessage "Message | $($PSStyle.Foreground.Red)$Local:Message" -PSColour Cyan;
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
		        [String]$UnicodePrefix
		    )
		    process {
		        if ($InputObject) {
		            Invoke-Verbose @InputObject;
		            return;
		        }
		        $Local:Params = @{
		            PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { '🔍' };
		            PSMessage = $Message;
		            PSColour = 'Yellow';
		            ShouldWrite = $Global:Logging.Verbose;
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
		        [String]$UnicodePrefix
		    )
		    process {
		        if ($InputObject) {
		            Invoke-Debug @InputObject;
		            return;
		        }
		        $Local:Params = @{
		            PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { '🐛' };
		            PSMessage = $Message;
		            PSColour = 'Magenta';
		            ShouldWrite = $Global:Logging.Debug;
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
		        [String]$UnicodePrefix
		    )
		    process {
		        if ($InputObject) {
		            Invoke-Info @InputObject;
		            return;
		        }
		        $Local:Params = @{
		            PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { 'ℹ️' };
		            PSMessage = $Message;
		            PSColour = 'Cyan';
		            ShouldWrite = $Global:Logging.Information;
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
		        # Ensure that the input buffer is flushed, otherwise the user can press escape before the loop starts and it would cancel it.
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
		                # Can't use -duration because it isn't available in PS 5.1
		                Start-Sleep -Milliseconds $Local:IntervalMinusElasped.TotalMilliseconds;
		            } else {
		                $Local:TimeLeft -= $Local:ElaspedTime;
		            }
		        } while ($Local:TimeLeft.TotalMilliseconds -gt 0)
		        if ($Local:TimeLeft -eq 0) {
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
		            # Calculate the estimated time remaining
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
		Export-ModuleMember -Function Get-SupportsUnicode, Invoke-Write, Invoke-Verbose, Invoke-Debug, Invoke-Info, Invoke-Warn, Invoke-Error, Invoke-FormattedError, Invoke-Timeout, Invoke-Progress;
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
		function Get-ScopeNameFormatted([Parameter(Mandatory)][Switch]$IsExit) {
		    [String]$Local:CurrentScope = (Get-StackTop).MyCommand.Name;
		    [String[]]$Local:PreviousScopes = (Get-Stack).GetEnumerator() | ForEach-Object { $_.MyCommand } | Sort-Object -Descending -Property Name | Select-Object -SkipLast 1;
		    [String]$Local:Scope = "$($Local:PreviousScopes -join ' > ')$(if ($Local:PreviousScopes.Count -gt 0) { if ($IsExit) { ' < ' } else { ' > ' } })$Local:CurrentScope";
		    return $Local:Scope;
		}
		function Get-FormattedParameters(
		    [Parameter()]
		    [String[]]$IgnoreParams = @()
		) {
		    [System.Collections.IDictionary]$Local:Params = (Get-StackTop).BoundParameters;
		    if ($null -ne $Local:Params -and $Local:Params.Count -gt 0) {
		        [String[]]$Local:ParamsFormatted = $Local:Params.GetEnumerator() | Where-Object { $_.Key -notin $IgnoreParams } | ForEach-Object { "$($_.Key) = $($_.Value)" };
		        [String]$Local:ParamsFormatted = $Local:ParamsFormatted -join "`n";
		        return "$Local:ParamsFormatted";
		    }
		    return $null;
		}
		function Get-FormattedReturnValue(
		    [Parameter()]
		    [Object]$ReturnValue
		) {
		    function Format([Object]$Value) {
		        switch ($Value) {
		            { $_ -is [System.Collections.HashTable] } { "`n$Script:Tab$(([HashTable]$Value).GetEnumerator().ForEach({ "$($_.Key) = $($_.Value)" }) -join "`n$Script:Tab")" }
		            default { $ReturnValue }
		        };
		    }
		    if ($null -ne $ReturnValue) {
		        [String]$Local:FormattedValue = if ($ReturnValue -is [Array]) {
		            "$(($ReturnValue | ForEach-Object { Format $_ }) -join "`n$Script:Tab")"
		        } else {
		            Format -Value $ReturnValue;
		        }
		        return "Return Value: $Local:FormattedValue";
		    };
		    return $null;
		}
		function Enter-Scope(
		    [Parameter()][ValidateNotNull()]
		    [String[]]$IgnoreParams = @(),
		    [Parameter()][ValidateNotNull()]
		    [System.Management.Automation.InvocationInfo]$Invocation = (Get-PSCallStack)[0].InvocationInfo
		) {
		    (Get-Stack).Push($Invocation);
		    [String]$Local:ScopeName = Get-ScopeNameFormatted -IsExit:$False;
		    [String]$Local:ParamsFormatted = Get-FormattedParameters -IgnoreParams:$IgnoreParams;
		    @{
		        PSMessage   = "$Local:ScopeName$(if ($Local:ParamsFormatted) { "`n$Local:ParamsFormatted" })";
		        PSColour    = 'Blue';
		        PSPrefix    = '❯❯';
		        ShouldWrite = $Global:Logging.Verbose;
		    } | Invoke-Write;
		}
		function Exit-Scope(
		    [Parameter()][ValidateNotNull()]
		    [System.Management.Automation.InvocationInfo]$Invocation = (Get-PSCallStack)[0].InvocationInfo,
		    [Parameter()]
		    [Object]$ReturnValue
		) {
		    [String]$Local:ScopeName = Get-ScopeNameFormatted -IsExit:$True;
		    [String]$Local:ReturnValueFormatted = Get-FormattedReturnValue -ReturnValue $ReturnValue;
		    @{
		        PSMessage   = "$Local:ScopeName$(if ($Local:ReturnValueFormatted) { "`n$Script:Tab$Local:ReturnValueFormatted" })";
		        PSColour    = 'Blue';
		        PSPrefix    = '❮❮';
		        ShouldWrite = $Global:Logging.Verbose;
		    } | Invoke-Write;
		    (Get-Stack).Pop() | Out-Null;
		}
		Export-ModuleMember -Function Get-StackTop, Get-FormattedParameters, Get-FormattedReturnValue, Get-ScopeNameFormatted, Enter-Scope,Exit-Scope;
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
		        } catch {
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
		        [Parameter(HelpMessage='The error record that caused the exit, if any.')]
		        [System.Management.Automation.ErrorRecord]$ErrorRecord,
		        [Parameter()]
		        [ValidateNotNullOrEmpty()]
		        [Switch]$DontExit
		    )
		    [String]$Local:ExitDescription = $Global:ExitCodes[$ExitCode];
		    if ($null -ne $Local:ExitDescription -and $Local:ExitDescription.Length -gt 0) {
		        Invoke-Error $Local:ExitDescription;
		    }
		    if ($ErrorRecord) {
		        [System.Exception]$Local:DeepestException = $ErrorRecord.Exception;
		        [String]$Local:DeepestMessage = $Local:DeepestException.Message;
		        [System.Management.Automation.InvocationInfo]$Local:DeepestInvocationInfo = $ErrorRecord.InvocationInfo;
		        while ($Local:DeepestException.InnerException) {
		            Invoke-Debug "Getting inner exception... (Current: $Local:DeepestException)";
		            Invoke-Debug "Inner exception: $($Local:DeepestException.InnerException)";
		            if (-not $Local:DeepestException.InnerException.ErrorRecord) {
		                Invoke-Debug "Inner exception has no error record, breaking to keep the current exceptions information...";
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
		            Invoke-FormattedError -InvocationInfo $Local:DeepestInvocationInfo -Message $Local:DeepestMessage;
		        } elseif ($Local:DeepestMessage) {
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
		        } else {
		            [System.Management.Automation.ErrorCategory]$Local:Catagory = $Local:DeepestException.ErrorRecord.CategoryInfo.Category;
		        }
		        [System.Management.Automation.ErrorRecord]$Local:ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
		            [System.Exception]$Local:DeepestException,
		            'FailedExit',
		            $Local:Catagory,
		            $ExitCode
		        );
		        throw $Local:ErrorRecord;
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
		    } else {
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
		Export-ModuleMember -Function Invoke-Handlers, Invoke-FailedExit, Invoke-QuickExit, Register-ExitHandler, Register-ExitCode;
    };`
	"05-Assert" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
        function Assert-NotNull(
		    [Parameter(Mandatory, ValueFromPipeline)]
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
        $Script:NOT_ADMINISTRATOR = Register-ExitCode -Description "Not running as administrator!`nPlease re-run your terminal session as Administrator, and try again.";
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
		$Script:UNABLE_TO_INSTALL_MODULE = Register-ExitCode -Description 'Unable to install module.';
		$Script:MODULE_NOT_INSTALLED = Register-ExitCode -Description 'Module not installed and no-install is set.';
		$Script:ImportedModules = [System.Collections.Generic.List[String]]::new();
		function Invoke-EnsureModules {
		    [CmdletBinding()]
		    param (
		        [Parameter(Mandatory)]
		        [ValidateNotNullOrEmpty()]
		        [String[]]$Modules,
		        [Parameter(HelpMessage = 'Do not install the module if it is not installed.')]
		        [switch]$NoInstall
		    )
		    begin { Enter-Scope -Invocation $MyInvocation; }
		    end { Exit-Scope -Invocation $MyInvocation; }
		    process {
		        try {
		            $ErrorActionPreference = 'Stop';
		            Get-PackageProvider -Name NuGet | Out-Null;
		        } catch {
		            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$False;
		            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted;
		        }
		        foreach ($Local:Module in $Modules) {
		            if (Test-Path -Path $Local:Module) {
		                Invoke-Debug "Module '$Local:Module' is a local path to a module, importing...";
		                $Script:ImportedModules.Add(($Local:Module | Split-Path -LeafBase));
		            } elseif (-not (Get-Module -ListAvailable -Name $Local:Module)) {
		                if ($NoInstall) {
		                    Invoke-Error -Message "Module '$Local:Module' is not installed, and no-install is set.";
		                    Invoke-FailedExit -ExitCode $Script:MODULE_NOT_INSTALLED;
		                }
		                Invoke-Info "Module '$Local:Module' is not installed, installing...";
		                try {
		                    Install-Module -Name $Local:Module -AllowClobber -Scope CurrentUser -Force;
		                    $Script:ImportedModules.Add($Local:Module);
		                } catch {
		                    Invoke-Error -Message "Unable to install module '$Local:Module'.";
		                    Invoke-FailedExit -ExitCode $Script:UNABLE_TO_INSTALL_MODULE;
		                }
		            } else {
		                Invoke-Debug "Module '$Local:Module' is installed.";
		                $Script:ImportedModules.Add($Local:Module);
		            }
		            Invoke-Debug "Importing module '$Local:Module'...";
		            Import-Module -Name $Local:Module -Global;
		        }
		        Invoke-Verbose -Message 'All modules are installed.';
		    }
		}
		$Script:WifiXmlTemplate = "<?xml version=""1.0""?>
		<WLANProfile xmlns=""http://www.microsoft.com/networking/WLAN/profile/v1"">
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
		";
		$Private:NO_CONNECTION_AFTER_SETUP = Register-ExitCode -Description 'Failed to connect to the internet after network setup.';
		function Invoke-EnsureNetwork(
		    [Parameter(HelpMessage = 'The name of the network to connect to.')]
		    [ValidateNotNullOrEmpty()]
		    [String]$Name,
		    [Parameter(HelpMessage = 'The password of the network to connect if required.')]
		    [SecureString]$Password
		) {
		    begin { Enter-Scope -Invocation $MyInvocation; }
		    end { Exit-Scope -Invocation $MyInvocation; }
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
		            # Remove the password if it is not provided.
		            if (-not $PlainPassword) {
		                $Local:XmlContent.WLANProfile.MSM.security.RemoveChild($Local:XmlContent.WLANProfile.MSM.security.sharedKey) | Out-Null;
		            }
		            $Local:XmlContent.InnerXml | Out-File -FilePath $Local:ProfileFile -Encoding UTF8;
		            if ($WhatIfPreference) {
		                Invoke-Info -Message 'WhatIf is set, skipping network setup...';
		                return $true;
		            } else {
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
		Export-ModuleMember -Function Invoke-EnsureAdministrator, Invoke-EnsureUser, Invoke-EnsureModules, Invoke-EnsureNetwork;
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
		function Install-Requirements {
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
		}
		function Test-ManagedPackage(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [String]$PackageName
		) {
		    @{
		        PSPrefix = '🔍';
		        PSMessage = "Checking if package '$PackageName' is installed...";
		        PSColour = 'Yellow';
		    } | Invoke-Write;
		    # if ($PackageVersion) {
		    #     $Local:PackageArgs['Version'] = $PackageVersion;
		    # }
		    [Boolean]$Local:Installed = & $Script:PackageManagerDetails.Executable $Script:PackageManagerDetails.Commands.List $Script:PackageManagerDetails.Options.Common $PackageName;
		    Invoke-Verbose "Package '$PackageName' is $(if (-not $Local:Installed) { 'not ' })installed.";
		    return $Local:Installed;
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
		    # [Parameter()]
		    # [ValidateNotNullOrEmpty()]
		    # [String]$PackageVersion
		) {
		    @{
		        PSPrefix = '📦';
		        PSMessage = "Installing package '$Local:PackageName'...";
		        PSColour = 'Green';
		    } | Invoke-Write;
		    # if ($PackageVersion) {
		    #     $Local:PackageArgs['Version'] = $PackageVersion;
		    # }
		    [System.Diagnostics.Process]$Local:Process = Start-Process -FilePath $Script:PackageManagerDetails.Executable -ArgumentList (@($Script:PackageManagerDetails.Commands.Install) + $Script:PackageManagerDetails.Options.Common + @($PackageName)) -NoNewWindow -PassThru -Wait;
		    if ($Local:Process.ExitCode -ne 0) {
		        Invoke-Error "There was an issue while installing $Local:PackageName.";
		        Invoke-FailedExit -ExitCode $Local:Process.ExitCode -DontExit:$NoFail;
		    }
		}
		function Uninstall-ManagedPackage() {
		}
		function Update-ManagedPackage(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [String]$PackageName
		) {
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
		Install-Requirements;
		Export-ModuleMember -Function Test-ManagedPackage, Install-ManagedPackage, Uninstall-Package, Update-ManagedPackage;
    };`
	"50-Input" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
        Function Clear-HostLight (
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
		function Invoke-WithColour {
		    Param(
		        [Parameter(Mandatory)]
		        [ValidateNotNullOrEmpty()]
		        [ScriptBlock]$ScriptBlock
		    )
		    try {
		        $Local:UI = $Host.UI.RawUI;
		        $Local:PrevForegroundColour = $Local:UI.ForegroundColor;
		        $Local:PrevBackgroundColour = $Local:UI.BackgroundColor;
		        $Local:UI.ForegroundColor = 'Yellow';
		        $Local:UI.BackgroundColor = 'Black';
		        $Local:Return = & $ScriptBlock
		    } finally {
		        $Local:UI.ForegroundColor = $Local:PrevForegroundColour;
		        $Local:UI.BackgroundColor = $Local:PrevBackgroundColour;
		    }
		    return $Local:Return;
		}
		function Get-UserInput {
		    Param(
		        [Parameter(Mandatory)]
		        [ValidateNotNullOrEmpty()]
		        [String]$Title,
		        [Parameter(Mandatory)]
		        [ValidateNotNullOrEmpty()]
		        [String]$Question
		    )
		    return Invoke-WithColour {
		        Write-Host -ForegroundColor DarkCyan $Title;
		        Write-Host -ForegroundColor DarkCyan "$($Question): " -NoNewline;
		        # Clear line buffer to not get old input.
		        $Host.UI.RawUI.FlushInputBuffer();
		        return $Host.UI.ReadLine();
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
		        0 { $true }
		        Default { $false }
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
		        [Array]$Choices,
		        [Parameter()]
		        [ValidateNotNullOrEmpty()]
		        [Int]$DefaultChoice = 0
		    )
		    return Invoke-WithColour {
		        [HashTable]$Local:BaseFormat = @{
		            PSColour    = 'DarkCyan';
		            PSPrefix    = '▶';
		            ShouldWrite = $true;
		        };
		        Invoke-Write @Local:BaseFormat -PSMessage $Title;
		        Invoke-Write @Local:BaseFormat -PSMessage $Question;
		        $Local:PreviousTabFunction = (Get-PSReadLineKeyHandler -Chord Tab).Function;
		        if (-not $Local:PreviousTabFunction) {
		            $Local:PreviousTabFunction = 'TabCompleteNext';
		        }
		        $Script:ChoicesList = $Choices;
		        Set-PSReadLineKeyHandler -Chord Tab -ScriptBlock {
		            Param([System.ConsoleKeyInfo]$Key, $Arg)
		            $Line = $null;
		            $Cursor = $null;
		            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$Line, [ref]$Cursor);
		            $MatchingInput = $Line.Substring(0, $Cursor);
		            if ($Script:PreviewingChoices -and $Line -eq $Script:PreviewingInput) {
		                if ($Script:ChoicesGoneThrough -eq $Script:MatchedChoices.Count - 1) {
		                    $Script:ChoicesGoneThrough = 0;
		                } else {
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
		            } elseif ($Script:MatchedChoices.Count -eq 1) {
		                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $MatchingInput.Length, $Script:MatchedChoices);
		            }
		        }
		        $Local:PreviousEnterFunction = (Get-PSReadLineKeyHandler -Chord Enter).Function;
		        $Script:PressedEnter = $false;
		        Set-PSReadLineKeyHandler -Chord Enter -ScriptBlock {
		            Param([System.ConsoleKeyInfo]$Key, $Arg)
		            $Script:PressedEnter = $true;
		            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine($Key, $Arg);
		        };
		        $Local:PreviousCtrlCFunction = (Get-PSReadLineKeyHandler -Chord Ctrl+c).Function;
		        $Script:ShouldAbort = $false;
		        Set-PSReadLineKeyHandler -Chord Ctrl+c -ScriptBlock {
		            Param([System.ConsoleKeyInfo]$Key, $Arg)
		            $Script:ShouldAbort = $true;
		            [Microsoft.PowerShell.PSConsoleReadLine]::CancelLine($Key, $Arg);
		            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine($Key, $Arg);
		        };
		        $Local:FirstRun = $true;
		        $Host.UI.RawUI.FlushInputBuffer();
		        Clear-HostLight -Count 0; # Clear the line buffer to get rid of the >> prompt.
		        Invoke-Write @Local:BaseFormat -PSMessage "Enter one of the following: $($Choices -join ', ')";
		        Write-Host ">> $($PSStyle.Foreground.FromRgb(40, 44, 52))$($Choices[$DefaultChoice])" -NoNewline;
		        Write-Host "`r>> " -NoNewline;
		        do {
		            $Local:Selection = [Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($Host.Runspace, $ExecutionContext, $?);
		            if (-not $Local:Selection -and $Local:FirstRun) {
		                $Local:Selection = $Choices[$DefaultChoice];
		                Clear-HostLight -Count 1;
		            } elseif ($Local:Selection -notin $Choices) {
		                $Local:ClearLines = if ($Local:FailedAtLeastOnce -and $Script:PressedEnter) { 2 } else { 1 };
		                Clear-HostLight -Count $Local:ClearLines;
		                Invoke-Write @Local:BaseFormat -PSMessage "Invalid selection, please try again...";
		                $Host.UI.Write('>> ');
		                $Local:FailedAtLeastOnce = $true;
		                $Script:PressedEnter = $false;
		            }
		            $Local:FirstRun = $false;
		        } while ($Local:Selection -notin $Choices -and -not $Script:ShouldAbort);
		        Set-PSReadLineKeyHandler -Chord Tab -Function $Local:PreviousTabFunction;
		        Set-PSReadLineKeyHandler -Chord Enter -Function $Local:PreviousEnterFunction;
		        Set-PSReadLineKeyHandler -Chord Ctrl+c -Function $Local:PreviousCtrlCFunction;
		        if ($Script:ShouldAbort) {
		            throw [System.Management.Automation.PipelineStoppedException]::new();
		        }
		        return $Choices.IndexOf($Local:Selection);
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
		            Invoke-Info "No Item was selected, re-running selection...";
		        }
		    }
		    $Local:Selection -and -not $AllowNone | Assert-NotNull -Message "Failed to select a $ItemName.";
		    return $Local:Selection;
		}
		Export-ModuleMember -Function Get-UserInput, Get-UserConfirmation, Get-UserSelection, Get-PopupSelection;
    };`
	"50-Module" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
        function Import-DownloadableModule {
		    Param(
		        [Parameter(Mandatory)]
		        [ValidateNotNullOrEmpty()]
		        [String]$Name
		    )
		    $Local:Module = Get-Module -ListAvailable | Where-Object { $_.Name -eq $Name } | Select-Object -First 1;
		    if ($Local:Module) {
		        Invoke-Verbose -Message "Importing previously installed module $Name...";
		        Import-Module $Local:Module;
		        return;
		    }
		    Invoke-Verbose "Ensuring NuGet is installed..."
		    Install-PackageProvider -Name NuGet -Confirm:$false;
		    Invoke-Verbose "Installing module $Name...";
		    Install-Module -Name $Name -Scope CurrentUser -Confirm:$false -Force;
		    Invoke-Verbose "Importing module $Name...";
		    Import-Module -Name $Name;
		}
		Export-ModuleMember -Function Import-DownloadableModule;
    };`
	"99-Cache" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
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
    };`
	"99-Connection" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
        function Connect-Service(
		    [Parameter(Mandatory)]
		    [ValidateSet('ExchangeOnline', 'SecurityComplience', 'AzureAD', 'Graph', 'Msol')]
		    [String[]]$Services,
		    [Parameter()]
		    [String[]]$Scopes,
		    # If true prompt for confirmation if already connected.
		    [Switch]$DontConfirm
		) {
		    foreach ($Local:Service in $Services) {
		        Invoke-Info "Connecting to $Local:Service...";
		        $Local:Connected = try {
		            $ErrorActionPreference = 'SilentlyContinue'; # For some reason AzureAD loves to be noisy.
		            switch ($Service) {
		                'ExchangeOnline' {
		                    Get-ConnectionInformation | Select-Object -ExpandProperty UserPrincipalName;
		                }
		                'SecurityComplience' {
		                    Get-IPPSSession | Select-Object -ExpandProperty UserPrincipalName;
		                }
		                'AzureAD' {
		                    Get-AzureADCurrentSessionInfo | Select-Object -ExpandProperty Account;
		                }
		                'Graph' {
		                    Get-MgDomain | Where-Object { $_.IsDefault -eq $True } | Select-Object -First 1 -ExpandProperty Id;
		                }
		                'Msol' {
		                    Get-MsolCompanyInformation | Select-Object -ExpandProperty DisplayName;
		                }
		            }
		        } catch {
		            $null
		        }
		        if ($Local:Connected) {
		            if (!$DontConfirm) {
		                $Local:Continue = Get-UserConfirmation -Title "Already connected to $Local:Service as [$Local:Connected]" -Question 'Do you want to continue?' -DefaultChoice $true;
		                if ($Local:Continue) {
		                    continue;
		                }
		                Invoke-Verbose 'Continuing with current connection...';
		            } else {
		                Invoke-Verbose "Already connected to $Local:Service. Skipping..."
		                continue
		            }
		        }
		        try {
		            Invoke-Info "Getting credentials for $Local:Service...";
		            switch ($Local:Service) {
		                'ExchangeOnline' {
		                    Connect-ExchangeOnline;
		                }
		                'SecurityComplience' {
		                    Connect-IPPSSession;
		                }
		                'AzureAD' {
		                    Connect-AzureAD;
		                }
		                'Graph' {
		                    Connect-MgGraph -NoWelcome -Scopes $Scopes;
		                }
		                'Msol' {
		                    Connect-MsolService;
		                }
		            }
		        } catch {
		            Invoke-Error "Failed to connect to $Local:Service";
		            Invoke-FailedExit -ExitCode 1002 -ErrorRecord $_;
		        }
		    }
		}
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
		            New-Item -Path $Local:CurrentPath -Force -ItemType RegistryKey;
		        }
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
		    Invoke-EnsureRegistryPath -Root $Path.Substring(0, 4) -Path $Path.Substring(5);
		    if ($PSCmdlet.ShouldProcess($Path, 'Set')) {
		        Invoke-Verbose "Setting registry key '$Path'...";
		        Set-ItemProperty -Path $Path -Name $Key -Value $Value -Type $Kind;
		    }
		}
		Export-ModuleMember -Function New-RegistryKey, Remove-RegistryKey, Set-RegistryKey, Test-RegistryKey;
    };`
	"99-UsersAndAccounts" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
        function Local:Get-GroupByInputOrName(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [ValidateScript({ $_ -is [String] -or $_ -is [ADSI] })]
		    [Object]$InputObject
		) {
		    begin { Enter-Scope; }
		    end { Exit-Scope -ReturnValue $Local:Group; }
		    process {
		        if ($InputObject -is [String]) {
		            [ADSI]$Local:Group = Get-Group -Name $InputObject;
		        } elseif ($InputObject.SchemaClassName -ne 'Group') {
		            Write-Error 'The supplied object is not a group.' -TargetObject $InputObject -Category InvalidArgument;
		        } else {
		            [ADSI]$Local:Group = $InputObject;
		        }
		        return $Local:Group;
		    }
		}
		function Local:Get-UserByInputOrName(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [ValidateScript({ $_ -is [String] -or $_ -is [ADSI] })]
		    [Object]$InputObject
		) {
		    begin { Enter-Scope; }
		    end { Exit-Scope -ReturnValue $Local:User; }
		    process {
		        if ($InputObject -is [String]) {
		            [ADSI]$Local:User = Get-User -Name $InputObject;
		        } elseif ($InputObject.SchemaClassName -ne 'User') {
		            Write-Error 'The supplied object is not a user.' -TargetObject $InputObject -Category InvalidArgument;
		        } else {
		            [ADSI]$Local:User = $InputObject;
		        }
		        return $Local:User;
		    }
		}
		function Get-FormattedUser(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [ValidateScript({ $_.SchemaClassName -eq 'User' })]
		    [ADSI]$User
		) {
		    begin { Enter-Scope; }
		    end { Exit-Scope -ReturnValue $Local:FormattedUser; }
		    process {
		        [String]$Local:Path = $User.Path.Substring(8); # Remove the WinNT:// prefix
		        [String[]]$Local:PathParts = $Local:Path.Split('/');
		        # The username is always last followed by the domain.
		        [HashTable]$Local:FormattedUser = @{
		            Name = $Local:PathParts[$Local:PathParts.Count - 1]
		            Domain = $Local:PathParts[$Local:PathParts.Count - 2]
		        };
		        return $Local:FormattedUser;
		    }
		}
		function Get-FormattedUsers(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [ADSI[]]$Users
		) {
		    begin { Enter-Scope; }
		    end { Exit-Scope -ReturnValue $Local:FormattedUsers; }
		    process {
		        $Local:FormattedUsers = $Users | ForEach-Object {
		            Get-FormattedUser -User $_;
		        };
		        return $Local:FormattedUsers;
		    }
		}
		function Test-MemberOfGroup(
		    [Parameter(Mandatory)]
		    [Object]$Group,
		    [Parameter(Mandatory)]
		    [Object]$Username
		) {
		    begin { Enter-Scope; }
		    end { Exit-Scope -ReturnValue $Local:User; }
		    process {
		        [ADSI]$Local:Group = Get-GroupByInputOrName -InputObject $Group;
		        [ADSI]$Local:User = Get-UserByInputOrName -InputObject $Username;
		        return $Local:Group.Invoke("IsMember", $Local:User.Path);
		    }
		}
		function Get-Group(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [String]$Name
		) {
		    begin { Enter-Scope; }
		    end { Exit-Scope -ReturnValue $Local:Group; }
		    process {
		        [ADSI]$Local:Group = [ADSI]"WinNT://$env:COMPUTERNAME/$Name,group";
		        return $Local:Group
		    }
		}
		function Get-Groups {
		    begin { Enter-Scope; }
		    end { Exit-Scope -ReturnValue $Local:Groups; }
		    process {
		        $Local:Groups = [ADSI]"WinNT://$env:COMPUTERNAME";
		        $Local:Groups.Children | Where-Object { $_.SchemaClassName -eq 'Group' };
		    }
		}
		function Get-GroupMembers(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [Object]$Group
		) {
		    begin { Enter-Scope; }
		    end { Exit-Scope -ReturnValue $Local:Members; }
		    process {
		        [ADSI]$Local:Group = Get-GroupByInputOrName -InputObject $Group;
		        $Group.Invoke("Members") `
		            | ForEach-Object { [ADSI]$_ } `
		            | Where-Object {
		                if ($_.Parent.Length -gt 8) {
		                    $_.Parent.Substring(8) -ne 'NT AUTHORITY'
		                } else {
		                    # This is a in-built user, skip it.
		                    $False
		                }
		            };
		    }
		}
		function Add-MemberToGroup(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [Object]$Group,
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [Object]$Username
		) {
		    begin { Enter-Scope; }
		    end { Exit-Scope; }
		    process {
		        [ADSI]$Local:Group = Get-GroupByInputOrName -InputObject $Group;
		        [ADSI]$Local:User = Get-UserByInputOrName -InputObject $Username;
		        if (Test-MemberOfGroup -Group $Local:Group -Username $Local:User) {
		            Invoke-Verbose "User $Username is already a member of group $Group.";
		            return $False;
		        }
		        Invoke-Verbose "Adding user $Name to group $Group...";
		        $Local:Group.Invoke("Add", $Local:User.Path);
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
		        if (-not (Test-MemberOfGroup -Group $Local:Group -Username $Local:User)) {
		            Invoke-Verbose "User $Member is not a member of group $Group.";
		            return $False;
		        }
		        Invoke-Verbose "Removing user $Name from group $Group...";
		        $Local:Group.Invoke("Remove", $Local:User.Path);
		        return $True;
		    }
		}
		Export-ModuleMember -Function Add-MemberToGroup, Get-FormattedUser, Get-FormattedUsers, Get-Group, Get-Groups, Get-GroupMembers, Get-UserByInputOrName, Remove-MemberFromGroup, Test-MemberOfGroup;
    };
}
using namespace Microsoft.Graph.Beta.PowerShell.Models;
[CmdletBinding()]
param()
function Get-IntuneGroup {
    $Local:GroupName = "Intune Users";
    $Local:IntuneGroup = Get-MgBetaGroup -Filter "displayName eq '$Local:GroupName'" -All:$true;
    if (-not $Local:IntuneGroup) {
        Invoke-Info "$Local:GroupName does not exists. Creating...";
        $Local:IntuneGroup = New-MgBetaGroup `
            -DisplayName $Local:GroupName `
            -MailEnabled:$False `
            -MailNickname "intune" `
            -SecurityEnabled:$True `
            -Description 'Group for users that are managed by Intune.';
    }
    return $IntuneGroup
}
function Local:Set-Configuration(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [MicrosoftGraphGroup]$IntuneGroup,
    [Parameter(Mandatory, ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [PSCustomObject]$Configuration,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ScriptBlock]$GetExistingConfiguration,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ScriptBlock]$UpdateConfiguration,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ScriptBlock]$NewConfiguration,
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [ScriptBlock]$NewConfigurationExtra,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ScriptBlock]$GetExistingAssignment,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ScriptBlock]$UpdateAssignment,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ScriptBlock]$NewAssignment
) {
    begin { Enter-Scope -IgnoreParams 'GetExistingConfiguration', 'UpdateConfiguration', 'NewConfiguration', 'NewConfigurationExtra', 'GetExistingAssignment', 'UpdateAssignment', 'NewAssignment' }
    end { Exit-Scope; }
    process {
        Trap {
            Invoke-Error 'Failed to set device compliance policy.';
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        }
        [String]$Local:ConfigurationName = $Configuration.displayName;
        $Local:ExistingConfiguration = $GetExistingConfiguration.InvokeReturnAsIs(@($Local:ConfigurationName));
        if ($null -ne $Local:ExistingConfiguration) {
            Invoke-Info "Updating configuration '$Local:ConfigurationName'.";
            # Compare the existing policy to the new policy
            [Boolean]$Local:ConfigurationIsDifferent = $false;
            foreach ($Local:Property in $Configuration.GetEnumerator()) {
                if ($Local:Property.Value -ne $Local:ExistingConfiguration.AdditionalProperties."$($Local:Property.Name)") {
                    Invoke-Info "Property '$($Local:Property.Name)' is different, updating.";
                    Invoke-Debug "Old: $($Local:ExistingConfiguration.AdditionalProperties.$Local:Property.Name)";
                    Invoke-Debug "New: $($Local:Property.Value)";
                    $Local:ConfigurationIsDifferent = $true;
                    break;
                }
                else {
                    Invoke-Debug "Property '$($Local:Property.Name)' is the same, skipping.";
                }
            }
            if (-not $Local:ConfigurationIsDifferent) {
                Invoke-Info "Configuration '$Local:ConfigurationName' is already set to the correct configuration.";
                return;
            }
            [String]$Local:ConfigurationId = $Local:ExistingConfiguration.Id;
            [String]$Local:JsonConfiguration = $Configuration | ConvertTo-Json -Depth 99;
            $UpdateConfiguration.InvokeReturnAsIs(@($Local:ConfigurationId, $Local:JsonConfiguration));
        }
        else {
            Invoke-Info "Creating configuration '$Local:ConfigurationName'.";
            if ($null -ne $NewConfigurationExtra) {
                $Configuration = $NewConfigurationExtra.InvokeReturnAsIs(@($Configuration));
            }
            [String]$Local:JsonConfiguration = $Configuration | ConvertTo-Json -Depth 99;
            try {
                $ErrorActionPreference = 'Stop';
                $Local:SubmittedConfiguration = $NewConfiguration.InvokeReturnAsIs(@($Local:JsonConfiguration));
            } catch {
                Invoke-Error 'There was an error creating the configuration.';
                Invoke-FailedExit -ExitCode 1001 -ErrorRecord $_;
            }
            [String]$Local:ConfigurationId = $Local:SubmittedConfiguration.Id;
        }
        # Assign the policy
        Invoke-Info "Assigning configuration '$Local:ConfigurationName'.";
        $Local:ExistingAssignment = $GetExistingAssignment.InvokeReturnAsIs(@($Local:ConfigurationId));
        $Local:Assignment = @{
            assignments = @(
                @{
                    id     = if ($Local:ExistingAssignment) { $Local:ExistingAssignment.Id } else { '00000000-0000-0000-0000-000000000000' };
                    target = @{
                        '@odata.type' = '#microsoft.graph.groupAssignmentTarget';
                        groupId       = $IntuneGroup.Id;
                    };
                }
            );
        } | ConvertTo-Json -Depth 99;
        if (-not $Local:ExistingAssignment) {
            Invoke-Info "Configuration '$Local:ConfigurationName' does not have an assignment, creating.";
            $NewAssignment.InvokeReturnAsIs(@($Local:ConfigurationId, $Local:Assignment));
        } else {
            Invoke-Info "Configuration '$Local:ConfigurationName' already has an assignment, updating.";
            $UpdateAssignment.InvokeReturnAsIs(@($Local:ConfigurationId, $Local:Assignment));
        }
    }
}
function Local:Set-DeviceCompliancePolicy(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [MicrosoftGraphGroup]$IntuneGroup,
    [Parameter(Mandatory, ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [PSCustomObject]$PolicyConfiguration
) {
    Set-Configuration `
        -IntuneGroup $IntuneGroup `
        -Configuration $PolicyConfiguration `
        -GetExistingConfiguration { param($Name) Get-MgBetaDeviceManagementDeviceCompliancePolicy -Filter "displayName eq '$Name'" } `
        -UpdateConfiguration { param($Id, $Json) Update-MgBetaDeviceManagementDeviceCompliancePolicy -DeviceCompliancePolicyId $Id -BodyParameter $Json } `
        -NewConfiguration { param($Json) New-MgBetaDeviceManagementDeviceCompliancePolicy -BodyParameter $Json } `
        -NewConfigurationExtra { param($Configuration) $Configuration | Add-Member -MemberType NoteProperty -Name 'scheduledActionsForRule' @(@{
                ruleName                      = 'PasswordRequired';
                scheduledActionConfigurations = @(@{
                        'actionType'                = 'block';
                        'gracePeriodHours'          = 0;
                        'notificationTemplateId'    = '';
                        'notificationMessageCCList' = @();
                    });
            }) } `
        -GetExistingAssignment { param($Id) Get-MgBetaDeviceManagementDeviceCompliancePolicyAssignment -DeviceCompliancePolicyId $Id } `
        -UpdateAssignment { param($Id, $Assignment) Invoke-MgGraphRequest -Method POST -Uri "/beta/deviceManagement/deviceCompliancePolicies/${Id}/assign" -Body $Assignment } `
        -NewAssignment { param($Id, $Assignment) Invoke-MgGraphRequest -Method POST -Uri "/beta/deviceManagement/deviceCompliancePolicies/${Id}/assign" -Body $Assignment }
}
function Local:New-CompliancePolicy(
    [Parameter(Mandatory, HelpMessage = 'The clean name of the device type.')][ValidateNotNullOrEmpty()][String]$Name,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$ODataType,
    [Parameter(Mandatory)][HashTable]$Configuration
) {
    $Configuration | Add-Member -MemberType NoteProperty -Name '@odata.type' -Value $ODataType;
    $Configuration | Add-Member -MemberType NoteProperty -Name 'RoleScopeIds' -Value @('0');
    $Configuration | Add-Member -MemberType NoteProperty -Name 'Id' -Value '00000000-0000-0000-0000-000000000000';
    $Configuration | Add-Member -MemberType NoteProperty -Name 'displayName' -Value "$Name - Baseline";
    $Configuration | Add-Member -MemberType NoteProperty -Name 'description' -Value "Baseline configuration profile for $Name devices.";
    return $Configuration;
}
function Get-CommonCompliance(
    [Parameter(Mandatory)]
    [ValidateSet('password', 'passcode')]
    [String]$PassVar,
    [Parameter(ParameterSetName = 'WithExpiration')]
    [Switch]$WithExpiration,
    [Parameter(ParameterSetName = 'WithExpiration')]
    [Int]$Expiration = 730,
    [Parameter()]
    [Switch]$WithHarden
) {
    $Local:Common = @{
        "${PassVar}Required"                        = $true;
        "${PassVar}RequiredType"                    = 'deviceDefault';
        "${PassVar}MinutesOfInactivityBeforeLock"   = 15;
    };
    if ($WithExpiration) {
        $Local:Common.Add("${PassVar}ExpirationDays", $Expiration);
    }
    if ($WithHarden) {
        $Local:Common.Add("${PassVar}BlockSimple", $true);
        $Local:Common.Add("${PassVar}MinimumLength", 6);
        $Local:Common.Add("${PassVar}PreviousP$($PassVar.SubString(1))BlockCount", 5);
    }
    return $Local:Common;
}
function New-DeviceCompliancePolicy_Windows {
    New-CompliancePolicy 'Windows' '#microsoft.graph.windows10CompliancePolicy' (@{
        passwordRequiredToUnlockFromIdle        = $true;
        passwordMinimumCharacterSetCount        = $null;
        requireHealthyDeviceReport      = $true;
        osMinimumVersion                = $null;
        osMaximumVersion                = $null;
        mobileOsMinimumVersion          = $null;
        mobileOsMaximumVersion          = $null;
        validOperatingSystemBuildRanges = @();
        tpmRequired                                 = $true;
        bitLockerEnabled                            = $true;
        secureBootEnabled                           = $true;
        codeIntegrityEnabled                        = $true;
        storageRequireEncryption                    = $true;
        earlyLaunchAntiMalwareDriverEnabled         = $false;
        # TODO: Figure out how to enable these
        #memoryIntegrityEnabled                      = $true;
        #kernelDmaProtectionEnabled                  = $true;
        #virtualizationBasedSecurityEnabled          = $true;
        #firmwareProtectionEnabled                   = $true;
        activeFirewallRequired                      = $true;
        defenderEnabled                             = $true;
        defenderVersion                             = $null;
        signatureOutOfDate                          = $true;
        rtpEnabled                                  = $true;
        antivirusRequired                           = $true;
        antiSpywareRequired                         = $true;
        deviceThreatProtectionEnabled               = $true;
        deviceThreatProtectionRequiredSecurityLevel = 'low';
        deviceCompliancePolicyScript = $null
        configurationManagerComplianceRequired      = $false;
    } + (Get-CommonCompliance -PassVar 'password' -WithExpiration -WithHarden));
}
function New-DeviceCompliancePolicy_Android {
    New-CompliancePolicy 'Android' '#microsoft.graph.androidWorkProfileCompliancePolicy' (@{
        requiredPasswordComplexity  = 'medium'
        securityPreventInstallAppsFromUnknownSources        = $false
        securityDisableUsbDebugging                         = $false
        securityRequireVerifyApps                           = $false
        securityBlockJailbrokenDevices                      = $false
        securityRequireSafetyNetAttestationBasicIntegrity   = $true
        securityRequireSafetyNetAttestationCertifiedDevice  = $true
        securityRequireGooglePlayServices                   = $true
        securityRequireUpToDateSecurityProviders            = $true
        securityRequireCompanyPortalAppIntegrity            = $true
        deviceThreatProtectionEnabled                   = $true
        deviceThreatProtectionRequiredSecurityLevel     = 'low'
        advancedThreatProtectionRequiredSecurityLevel   = 'low'
        osMinimumVersion = '11'
        storageRequireEncryption = $true
    } + (Get-CommonCompliance -PassVar 'password'));
}
function New-DeviceCompliancePolicy_MacOS {
    New-CompliancePolicy 'MacOS' '#microsoft.graph.macOSCompliancePolicy' (@{
        systemIntegrityProtectionEnabled    = $true
        deviceThreatProtectionEnabled       = $true
        storageRequireEncryption            = $true
        firewallEnabled                     = $true
        firewallBlockAllIncoming            = $false
        firewallEnableStealthMode           = $true
        gatekeeperAllowedAppSource          = 'macAppStoreAndIdentifiedDevelopers'
    } + (Get-CommonCompliance -PassVar 'password' -WithExpiration -WithHarden));
}
function New-DeviceCompliancePolicy_iOS {
    New-CompliancePolicy 'iOS' '#microsoft.graph.iosCompliancePolicy' (@{
        passcodeMinutesOfInactivityBeforeScreenTimeout = 15
        securityBlockJailbrokenDevices = $true
        deviceThreatProtectionEnabled = $true
        deviceThreatProtectionRequiredSecurityLevel = 'low'
        advancedThreatProtectionRequiredSecurityLevel = 'low'
        managedEmailProfileRequired = $false
    } + (Get-CommonCompliance -PassVar 'passcode' -WithExpiration -Expiration:65535 -WithHarden));
}
function Local:Set-DeviceConfigurationProfile(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [MicrosoftGraphGroup]$IntuneGroup,
    [Parameter(Mandatory, ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [PSCustomObject]$Configuration
) {
    begin { Enter-Scope; }
    end { Exit-Scope; }
    process {
        Set-Configuration `
            -IntuneGroup $IntuneGroup `
            -Configuration $Configuration `
            -GetExistingConfiguration { param($Name) Get-MgBetaDeviceManagementDeviceConfiguration -Filter "displayName eq '$Name'" } `
            -UpdateConfiguration { param($Id, $Json) Update-MgBetaDeviceManagementDeviceConfiguration -DeviceConfigurationId $Id -BodyParameter $Json } `
            -NewConfiguration { param($Json) New-MgBetaDeviceManagementDeviceConfiguration -BodyParameter $Json } `
            -GetExistingAssignment { param($Id) Get-MgBetaDeviceManagementDeviceConfigurationAssignment -DeviceConfigurationAssignmentId $Id } `
            -UpdateAssignment { param($Id, $Assignment) Invoke-MgGraphRequest -Method POST -Uri "/beta/deviceManagement/deviceConfigurations/${Id}/assign" -Body $Assignment } `
            -NewAssignment { param($Id, $Assignment) Invoke-MgGraphRequest -Method POST -Uri "/beta/deviceManagement/deviceConfigurations/${Id}/assign" -Body $Assignment }
    }
}
function Local:New-DeviceConfigurationProfile(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$OS,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Name,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [HashTable]$Configuration
) {
    $Configuration | Add-Member -MemberType NoteProperty -Name 'RoleScopeTagIds' -Value @('0');
    $Configuration | Add-Member -MemberType NoteProperty -Name 'Id' -Value '00000000-0000-0000-0000-000000000000';
    $Configuration | Add-Member -MemberType NoteProperty -Name 'displayName' -Value "$OS - $Name";
    $Configuration | Add-Member -MemberType NoteProperty -Name 'description' -Value "Configuration profile for $OS, configuring $Name items.";
    return $Configuration;
}
$Script:DeviceConfigurationProfiles = @(
    # (New-ConfigurationProfile 'Windows' 'Domain Policy' @{
    #     '@odata.type' = '#microsoft.graph.windowsDomainJoinConfiguration';
    #     computerNameStaticPrefix        = 'AMT-';
    #     computerNameSufixRandCharCount  = 12;
    #     activeDirectoryDomainName       = (Get-MgDomain | Where-Object { $_.IsDefault -eq $True } | Select-Object -ExpandProperty Id);
    # })
    (New-DeviceConfigurationProfile 'Windows' 'Debloat' @{
        '@odata.type' = '#microsoft.graph.windows10GeneralConfiguration';
        searchDisableUseLocation = $True;
        searchDisableLocation = $True;
        searchBlockWebResults = $True;
        diagnosticsDataSubmissionMode = 'basic';
        inkWorkspaceAccess = 'disabled';
        inkWorkspaceAccessState = 'blocked';
        inkWorkspaceBlockSuggestedApps = $True;
        lockScreenBlockCortana = $True;
        lockScreenBlockToastNotifications = $True;
        settingsBlockGamingPage = $True;
        cortanaBlocked = $True;
        windowsSpotlightBlocked = $True;
        smartScreenBlockPromptOverride = $True;
        internetSharingBlocked = $True;
        gameDvrBlocked = $True;
        uninstallBuiltInApps = $True;
    })
    # (New-DeviceConfigurationProfile 'Windows' 'Identity Protection' @{
    # })
    # TODO :: Printer Setup Conf
    # TODO :: Identity Protection Conf
    # E 6 - A A A N - N E E E N N
    # TODO :: Encryption Conf
    # TODO :: Firewall Conf
    # TODO :: Defender Conf
    # TODO :: OneDrive Conf
)
function Set-TemplatePolicies {
    ## Definitly these
    # Require multifactor authentication for admins
    # Require multifactor authentication for all users
    # Block Legacy Authentication
    ## Maybes these too?
    # Securing security info registration
    # Block access for unkown or unsupported device platform
    # Require password change for high-risk users
}
function Set-CustomPolicies {
    # Geoblock
    # Geoblock - Allow Travel
}

(New-Module -ScriptBlock $Global:EmbededModules['00-Environment'] -AsCustomObject -ArgumentList $MyInvocation.BoundParameters).'Invoke-RunMain'($MyInvocation, {
    Connect-Service -Services 'Graph' -Scopes DeviceManagementServiceConfig.ReadWrite.All,deviceManagementConfiguration.ReadWrite.All, Group.ReadWrite.All;
    # Set the MDM Authority
    Invoke-Info 'Ensuring the MDM Authority is set to Intune...';
    Update-MgOrganization -OrganizationId (Get-MgOrganization | Select-Object -ExpandProperty Id) -BodyParameter (@{ mobileDeviceManagementAuthority = 1; } | ConvertTo-Json);
    # Set the Connectors
    Invoke-Info 'Setting up the Intune Connectors...';
    Invoke-MgGraphRequest -Method POST -Uri 'beta/deviceManagement/dataProcessorServiceForWindowsFeaturesOnboarding' -Body (@{
        "@odata.type" = "#microsoft.graph.dataProcessorServiceForWindowsFeaturesOnboarding";
        hasValidWindowsLicense = $True;
        areDataProcessorServiceForWindowsFeaturesEnabled = $True;
    })
    # Setup the Intune Group
    [MicrosoftGraphGroup]$Local:IntuneGroup = Get-IntuneGroup
    Invoke-Info 'Setting up Intune device compliance policies...';
    [PSCustomObject[]]$Local:DeviceCompliancePolicies = @((New-DeviceCompliancePolicy_Windows), (New-DeviceCompliancePolicy_Android), (New-DeviceCompliancePolicy_MacOS), (New-DeviceCompliancePolicy_iOS));
    $Local:DeviceCompliancePolicies | ForEach-Object {
        Invoke-Info "Setting up device compliance policy '$($_.displayName)'.";
        Set-DeviceCompliancePolicy -IntuneGroup $Local:IntuneGroup -PolicyConfiguration $_;
    }
    Invoke-Info 'Setting up Intune device configuration profiles...';
    $Script:DeviceConfigurationProfiles | ForEach-Object {
        Invoke-Info "Setting up device configuration profile '$($_.displayName)'.";
        Set-DeviceConfigurationProfile -IntuneGroup $Local:IntuneGroup -Configuration $_;
    }
    Invoke-Info 'Setting up Intune Custom Configuration Profiles...';
    # TODO :: Set up custom configuration profiles
    # $Script:
    Invoke-Info 'Setting up Intune Conditional Access Policies...';
    # TODO :: Set up conditional access policies
});
