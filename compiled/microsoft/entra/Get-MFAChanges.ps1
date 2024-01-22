#Requires -Version 5.1

Param(
    [Parameter(Mandatory = $true)]
    [String]$Client,
    [String]$SharedFolder = "AMT",
    [String]$ReportsFolder = "Monthly Report",
    [String]$ExcelFileName = "MFA Numbers.xlsx",
    [String]$ClientsFolder = "$env:USERPROFILE\$SharedFolder\Clients - Documents"
)
$Global:CompiledScript = $true;
$Global:EmbededModules = [ordered]@{
    "00-Logging.psm1" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
        function Local:Get-SupportsUnicode {
		    $True
		    # $null -ne $env:WT_SESSION;
		}
		function Local:Invoke-Write {
		    [CmdletBinding()]
		    param (
		        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
		        [ValidateNotNullOrEmpty()]
		        [String]$PSMessage,
		        [Parameter(ValueFromPipelineByPropertyName, HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
		        [String]$PSPrefix,
		        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
		        [ValidateNotNullOrEmpty()]
		        [String]$PSColour,
		        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
		        [ValidateNotNullOrEmpty()]
		        [Boolean]$ShouldWrite,
		        [Parameter(ValueFromPipelineByPropertyName)]
		        [ValidateNotNullOrEmpty()]
		        [Switch]$NoNewLine
		    )
		    process {
		        if (-not $ShouldWrite) {
		            return;
		        }
		        $Local:FormattedMessage = if ($PSMessage.Contains("`n")) {
		            $PSMessage -replace "`n", "`n + ";
		        } else {
		            $PSMessage;
		        }
		        if (Get-SupportsUnicode -and $PSPrefix) {
		            Write-Host -ForegroundColor $PSColour -Object "$PSPrefix $Local:FormattedMessage" -NoNewline:$NoNewLine;
		        } else {
		            Write-Host -ForegroundColor $PSColour -Object "$Local:FormattedMessage" -NoNewline:$NoNewLine;
		        }
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
		    Invoke-Write @Local:BaseHash -PSMessage "File    | " -PSColour 'Cyan' -NoNewLine;
		    Invoke-Write @Local:BaseHash -PSMessage $Local:Script -PSColour 'Red';
		    Invoke-Write @Local:BaseHash -PSMessage "Line    | " -PSColour 'Cyan' -NoNewline;
		    Invoke-Write @Local:BaseHash -PSMessage $InvocationInfo.ScriptLineNumber -PSColour 'Red';
		    Invoke-Write @Local:BaseHash -PSMessage "Preview | " -PSColour 'Cyan' -NoNewLine;
		    Invoke-Write @Local:BaseHash -PSMessage $Local:TrimmedLine -PSColour 'Red';
		    Invoke-Write @Local:BaseHash -PSMessage "$Local:Underline" -PSColour 'Red';
		    if ($Local:Message) {
		        Invoke-Write @Local:BaseHash -PSMessage "Message | " -PSColour 'Cyan' -NoNewLine;
		        Invoke-Write @Local:BaseHash -PSMessage $Local:Message -PSColour 'Red';
		    }
		}
		function Invoke-Verbose(
		    [Parameter(Mandatory, HelpMessage = 'The message to write to the console.')]
		    [ValidateNotNullOrEmpty()]
		    [String]$Message,
		    [Parameter(HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
		    [ValidateNotNullOrEmpty()]
		    [Alias('Prefix')]
		    [String]$UnicodePrefix
		) {
		    $Local:Params = @{
		        PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { '🔍' };
		        PSMessage = $Message;
		        PSColour = 'Yellow';
		        ShouldWrite = $VerbosePreference -ne 'SilentlyContinue';
		    };
		    Invoke-Write @Local:Params;
		}
		function Invoke-Debug(
		    [Parameter(Mandatory, HelpMessage = 'The message to write to the console.')]
		    [ValidateNotNullOrEmpty()]
		    [String]$Message,
		    [Parameter(HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
		    [ValidateNotNullOrEmpty()]
		    [Alias('Prefix')]
		    [String]$UnicodePrefix
		) {
		    $Local:Params = @{
		        PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { '🐛' };
		        PSMessage = $Message;
		        PSColour = 'Magenta';
		        ShouldWrite = $DebugPreference -ne 'SilentlyContinue';
		    };
		    Invoke-Write @Local:Params;
		}
		function Invoke-Info(
		    [Parameter(Mandatory, HelpMessage = 'The message to write to the console.')]
		    [ValidateNotNullOrEmpty()]
		    [String]$Message,
		    [Parameter(HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
		    [ValidateNotNullOrEmpty()]
		    [Alias('Prefix')]
		    [String]$UnicodePrefix
		) {
		    $Local:Params = @{
		        PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { 'ℹ️' };
		        PSMessage = $Message;
		        PSColour = 'Cyan';
		        ShouldWrite = $True;
		    };
		    Invoke-Write @Local:Params;
		}
		function Invoke-Warn(
		    [Parameter(Mandatory, HelpMessage = 'The message to write to the console.')]
		    [ValidateNotNullOrEmpty()]
		    [String]$Message,
		    [Parameter(HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
		    [ValidateNotNullOrEmpty()]
		    [Alias('Prefix')]
		    [String]$UnicodePrefix
		) {
		    $Local:Params = @{
		        PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { '⚠️' };
		        PSMessage = $Message;
		        PSColour = 'Yellow';
		        ShouldWrite = $True;
		    };
		    Invoke-Write @Local:Params;
		}
		function Invoke-Error(
		    [Parameter(Mandatory, HelpMessage = 'The message to write to the console.')]
		    [ValidateNotNullOrEmpty()]
		    [String]$Message,
		    [Parameter(HelpMessage = 'The Unicode Prefix to use if the terminal supports Unicode.')]
		    [ValidateNotNullOrEmpty()]
		    [Alias('Prefix')]
		    [String]$UnicodePrefix
		) {
		    $Local:Params = @{
		        PSPrefix = if ($UnicodePrefix) { $UnicodePrefix } else { '❌' };
		        PSMessage = $Message;
		        PSColour = 'Red';
		        ShouldWrite = $True;
		    };
		    Invoke-Write @Local:Params;
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
		        [Int16]$Local:TimeLeft = $Timeout;
		        while ($Local:TimeLeft -gt 0) {
		            if ($AllowCancel -and [Console]::KeyAvailable) {
		                break;
		            }
		            Write-Progress `
		                -Activity $Activity `
		                -Status ($StatusMessage -f ([Math]::Floor($Local:TimeLeft) / 10)) `
		                -PercentComplete ($Local:TimeLeft / $Timeout * 100) `
		                -Completed:($Local:TimeLeft -eq 1)
		            $Local:TimeLeft -= 1;
		            Start-Sleep -Milliseconds 1000;
		        }
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
		Export-ModuleMember -Function Invoke-Write, Invoke-Verbose, Invoke-Debug, Invoke-Info, Invoke-Warn, Invoke-Error, Invoke-FormattedError, Invoke-Timeout;
    };`
	"00-Scope.psm1" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
        function Local:Get-ScopeNameFormatted(
		    [Parameter(Mandatory)][ValidateNotNull()]
		    [System.Management.Automation.InvocationInfo]$Invocation
		) {
		    [String]$ScopeName = $Invocation.MyCommand.Name;
		    [String]$ScopeName = if ($null -ne $ScopeName) { "Scope: $ScopeName" } else { 'Scope: Unknown' };
		    return $ScopeName;
		}
		function Enter-Scope(
		    [Parameter(Mandatory)][ValidateNotNull()]
		    [System.Management.Automation.InvocationInfo]$Invocation
		) {
		    [String]$Local:ScopeName = Get-ScopeNameFormatted -Invocation $Invocation;
		    [System.Collections.IDictionary]$Local:Params = $Invocation.BoundParameters;
		    [String]$Local:ParamsFormatted = if ($null -ne $Params -and $Params.Count -gt 0) {
		        [String[]]$ParamsFormatted = $Params.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)" };
		        [String]$Local:ParamsFormatted = $Local:ParamsFormatted -join "`n`t";
		        "Parameters: $Local:ParamsFormatted";
		    } else { 'Parameters: None'; }
		    Invoke-Verbose "Entered Scope`n`t$ScopeName`n`t$ParamsFormatted";
		}
		function Exit-Scope(
		    [Parameter(Mandatory)][ValidateNotNull()]
		    [System.Management.Automation.InvocationInfo]$Invocation,
		    [Object]$ReturnValue
		) {
		    [String]$Local:ScopeName = Get-ScopeNameFormatted -Invocation $Invocation;
		    if ($null -ne $ReturnValue) {
		        [String]$Local:FormattedValue = switch ($ReturnValue) {
		            { $_ -is [System.Collections.Hashtable] } { "`n`t$(([HashTable]$ReturnValue).GetEnumerator().ForEach({ "$($_.Key) = $($_.Value)" }) -join "`n`t")" }
		            default { $ReturnValue }
		        };
		        [String]$Local:ReturnValueFormatted = "Return Value: $Local:FormattedValue";
		    } else { [String]$Local:ReturnValueFormatted = 'Return Value: None'; };
		    Invoke-Verbose "Exited Scope`n`t$ScopeName`n`t$ReturnValueFormatted";
		}
		Export-ModuleMember -Function Enter-Scope,Exit-Scope;
    };`
	"01-Exit.psm1" = {
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
		    Invoke-Handlers;
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
	"05-Assert.psm1" = {
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
	"05-Ensure.psm1" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
        $Script:NOT_ADMINISTRATOR = Register-ExitCode -Description 'Not running as administrator.';
		function Invoke-EnsureAdministrator {
		    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
		        Invoke-Error 'Not running as administrator!  Please re-run your terminal session as Administrator, and try again.'
		        Invoke-FailedExit -ExitCode $Script:NOT_ADMINISTRATOR;
		    }
		    Invoke-Verbose -Message 'Running as administrator.';
		}
		$Script:NOT_USER = Register-ExitCode -Description 'Not running as user.';
		function Invoke-EnsureUser {
		    if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
		        Invoke-Error 'Not running as user!  Please re-run your terminal session as your normal User, and try again.'
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
		$Private:UNABLE_TO_SETUP_NETWORK = Register-ExitCode -Description 'Unable to setup network.';
		$Private:NETWORK_NOT_SETUP = Register-ExitCode -Description 'Network not setup, and no details provided.';
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
		            $Local:XmlContent | Out-File -FilePath $Local:ProfileFile -Encoding UTF8;
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
		                        Invoke-FailedExit -ExitCode $Script:FAILED_TO_CONNECT;
		                    }
		                    Start-Sleep -Seconds 1
		                    $Local:RetryCount += 1
		                }
		                Invoke-Info -Message 'Network setup successfully.';
		                return $true;
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
	"45-PackageManager.psm1" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
        $Local:PackageManager = switch ($env:OS) {
		    'Windows_NT' {
		        $Local:ChocolateyPath = "$($env:SystemDrive)\ProgramData\Chocolatey\bin\choco.exe";
		        if (Test-Path -Path $Local:ChocolateyPath) {
		            $Local:ChocolateyPath;
		        } else {
		            throw "Chocolatey is not installed on this system.";
		        }
		        return $Local:ChocolateyPath;
		    };
		    default {
		        throw "Unsupported operating system.";
		    };
		};
		function Test-Package(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [String]$PackageName,
		    [Parameter()]
		    [ValidateNotNullOrEmpty()]
		    [String]$PackageVersion
		) {
		    $Local:Params = @{
		        PSPrefix = '🔍';
		        PSMessage = "Checking if package '$PackageName' is installed...";
		        PSColour = 'Yellow';
		    };
		    Invoke-Write @Local:Params;
		    $Local:PackageArgs = @{
		        PackageName = $PackageName;
		        Force = $true;
		        Confirm = $false;
		    };
		    if ($PackageVersion) {
		        $Local:PackageArgs['Version'] = $PackageVersion;
		    }
		    & $Local:PackageManager list --local-only @Local:PackageArgs;
		}
		function Install-Package(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [String]$PackageName,
		    [Parameter()]
		    [ValidateNotNullOrEmpty()]
		    [String]$PackageVersion
		) {
		    $Local:Params = @{
		        PSPrefix = '📦';
		        PSMessage = "Installing package '$PackageName'...";
		        PSColour = 'Green';
		    };
		    Invoke-Write @Local:Params;
		    $Local:PackageArgs = @{
		        PackageName = $PackageName;
		        Force = $true;
		        Confirm = $false;
		    };
		    if ($PackageVersion) {
		        $Local:PackageArgs['Version'] = $PackageVersion;
		    }
		    & $Local:PackageManager install @Local:PackageArgs;
		}
    };`
	"50-Input.psm1" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
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
		    $Local:Result = Get-UserSelection -Title $Title -Question $Question -Choices @('&Yes', '&No') -DefaultChoice $Local:DefaultChoice;
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
		        $Host.UI.RawUI.FlushInputBuffer();
		        return $Host.UI.PromptForChoice('', '', $Choices, $DefaultChoice);
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
	"50-Module.psm1" = {
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
	"99-Connection.psm1" = {
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
		                    Get-MSGraphEnvironment | Select-Object -ExpandProperty Account;
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
	"99-Flag.psm1" = {
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
		Export-ModuleMember -Function Get-FlagPath,Get-RebootFlag,Get-RunningFlag;
    };`
	"99-Temp.psm1" = {
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
	"Environment.psm1" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
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
		        [Switch]$HideDisclaimer
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
		            [HashTable]$Local:CommonParams = @{};
		            [String[]]$Local:CopyParams = @('WhatIf','Verbose','Debug','ErrorAction','WarningAction','InformationAction','ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable');
		            foreach ($Local:Param in $Invocation.BoundParameters.Keys) {
		                if ($Local:CopyParams -contains $Local:Param) {
		                    $Local:CommonParams[$Local:Param] = $Invocation.BoundParameters[$Local:Param];
		                }
		            }
		            # Setup UTF8 encoding to ensure that all output is encoded correctly.
		            $Local:PreviousEncoding = [Console]::InputEncoding, [Console]::OutputEncoding;
		            $OutputEncoding = [Console]::InputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding;
		            if (-not $HideDisclaimer) {
		                Write-Host -ForegroundColor Yellow -Object '⚠️ Disclaimer: This script is provided "as is", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and non-infringement. In no event shall the author or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the script or the use or other dealings in the script.';
		            }
		            if ($Local:DontImport) {
		                Write-Verbose -Message '♻️ Skipping module import.';
		                return;
		            }
		            $Local:ImportedModules = [System.Collections.Generic.List[String]]::new();
		            if ($Global:CompiledScript) {
		                Write-Verbose -Message '✅ Script has been embeded with required modules.';
		                $Local:ToImport = $Global:EmbededModules;
		            } elseif (Test-Path -Path "$($MyInvocation.MyCommand.Module.Path | Split-Path -Parent)/../../.git") {
		                Write-Verbose -Message '✅ Script is in git repository; Using local files.';
		                $Local:ToImport = Get-ChildItem -Path "$($MyInvocation.MyCommand.Module.Path | Split-Path -Parent)/*.psm1";
		            } else {
		                $Local:RepoPath = "$($env:TEMP)/AMTScripts";
		                if (-not (Test-Path -Path $Local:RepoPath)) {
		                    Write-Verbose -Message '♻️ Cloning repository.';
		                    git clone https://github.com/AMTSupport/scripts.git $Local:RepoPath;
		                } else {
		                    Write-Verbose -Message '♻️ Updating repository.';
		                    git -C $Local:RepoPath pull;
		                }
		                Write-Verbose -Message '♻️ Collecting common modules.';
		                $Local:ToImport = Get-ChildItem -Path "$Local:RepoPath/src/common/*.psm1";
		            }
		            Write-Verbose -Message "♻️ Importing $($Local:ToImport.Count) modules.";
		            if ($Global:CompiledScript) {
		                Write-Verbose -Message "✅ Modules to import: `n`t$($Local:ToImport.Keys -join "`n`t")";
		                foreach ($Local:Module in $Local:ToImport.GetEnumerator()) {
		                    $Local:ModuleKey = $Local:Module.Key;
		                    $Local:ModuleDefinition = $Local:Module.Value;
		                    $Local:Module = New-Module -ScriptBlock $Local:ModuleDefinition -Name $Local:ModuleKey | Import-Module -Global -Force -ArgumentList $Local:CommonParams;
		                }
		            } else {
		                Write-Verbose -Message "✅ Modules to import: `n`t$($Local:ToImport.Name -join "`n`t")";
		                Import-Module -Name $Local:ToImport.FullName -Global -ArgumentList $Local:CommonParams;
		            }
		            $Local:ImportedModules += $Local:ToImport;
		        }
		        process {
		            try {
		                # TODO :: Fix this, it's not working as expected
		                # If the script is being run directly, invoke the main function
		                # if ($Invocation.CommandOrigin -eq 'Runspace') {
		                Invoke-Verbose -UnicodePrefix '🚀' -Message 'Running main function.';
		                & $Main;
		            } catch {
		                if ($_.FullyQualifiedErrorId -eq 'QuickExit') {
		                    Invoke-Verbose -UnicodePrefix '✅' -Message 'Main function finished successfully.';
		                } elseif ($_.FullyQualifiedErrorId -eq 'FailedExit') {
		                    [Int16]$Local:ExitCode = $_.TargetObject;
		                    Invoke-Verbose -Message "Script exited with an error code of $Local:ExitCode.";
		                    $LASTEXITCODE = $Local:ExitCode;
		                } else {
		                    Invoke-Error 'Uncaught Exception during script execution';
		                    Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_ -DontExit;
		                }
		            } finally {
		                Invoke-Handlers;
		                ([Int16]$Local:ModuleCount, [String[]]$Local:ModuleNames) = if ($Global:CompiledScript) {
		                    $Local:ImportedModules.GetEnumerator().Count, $Local:ImportedModules.GetEnumerator().Keys
		                } else {
		                    $Local:ImportedModules.Count, $Local:ImportedModules
		                };
		                if (-not $Local:DontImport) {
		                    Invoke-Verbose -Prefix '♻️' -Message "Cleaning up $($Local:ModuleCount) imported modules.";
		                    Invoke-Verbose -Prefix '✅' -Message "Removing modules: `n`t$($Local:ModuleNames -join "`n`t")";
		                    if ($Global:CompiledScript) {
		                        $Local:ImportedModules.Keys | ForEach-Object {
		                            Remove-Module -Name $_ -Force;
		                        };
		                        $Global:CompiledScript = $null;
		                        $Global:EmbededModules = $null;
		                    }
		                    else {
		                        $Local:ImportedModules | ForEach-Object {
		                            Remove-Module -Name $_.BaseName -Force;
		                        }
		                    }
		                }
		                [Console]::InputEncoding, [Console]::OutputEncoding = $Local:PreviousEncoding;
		            }
		        }
		    }
		    [Boolean]$Local:Verbose = Get-OrFalse $Invocation.BoundParameters 'Verbose';
		    [Boolean]$Local:Debug = Get-OrFalse $Invocation.BoundParameters 'Debug';
		    Invoke-Inner -Invocation $Invocation -Main $Main -DontImport:$DontImport -HideDisclaimer:$HideDisclaimer -Verbose:$Local:Verbose -Debug:$Local:Debug;
		}
		Export-ModuleMember -Function Invoke-RunMain;
    };
}
$Script:NULL_ARGUMENT = 1000;
$Script:FAILED_EXPECTED_VALUE = 1004;
function Assert-NotNull([Parameter(Mandatory, ValueFromPipeline)][Object]$Object, [String]$Message) {
    if ($null -eq $Object -or $Object -eq '') {
        if ($null -eq $Message) {
            Write-Host -ForegroundColor Red -Object 'Object is null';
            Invoke-FailedExit -ExitCode $Script:NULL_ARGUMENT;
        } else {
            Write-Host -ForegroundColor Red -Object $Message;
            Invoke-FailedExit -ExitCode $Script:NULL_ARGUMENT;
        }
    }
}
function Assert-Equals([Parameter(Mandatory, ValueFromPipeline)][Object]$Object, [Parameter(Mandatory)][Object]$Expected, [String]$Message) {
    if ($Object -ne $Expected) {
        if ($null -eq $Message) {
            Write-Host -ForegroundColor Red -Object "Object [$Object] does not equal expected value [$Expected]";
            Invoke-FailedExit -ExitCode $Script:FAILED_EXPECTED_VALUE;
        } else {
            Write-Host -ForegroundColor Red -Object $Message;
            Invoke-FailedExit -ExitCode $Script:FAILED_EXPECTED_VALUE;
        }
    }
}
function Get-ScopeFormatted([Parameter(Mandatory)][System.Management.Automation.InvocationInfo]$Invocation) {
    $Invocation | Assert-NotNull -Message 'Invocation was null';
    [String]$ScopeName = $Invocation.MyCommand.Name;
    [String]$ScopeName = if ($null -ne $ScopeName) { "Scope: $ScopeName" } else { 'Scope: Unknown' };
    $ScopeName
}
function Enter-Scope([Parameter(Mandatory)][System.Management.Automation.InvocationInfo]$Invocation) {
    $Invocation | Assert-NotNull -Message 'Invocation was null';
    [String]$Local:ScopeName = Get-ScopeFormatted -Invocation $Invocation;
    $Local:Params = $Invocation.BoundParameters
    if ($null -ne $Params -and $Params.Count -gt 0) {
        [String[]]$ParamsFormatted = $Params.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)" };
        if ($PSVersionTable.PSVersion.Major -ge 6 -and $PSVersionTable.PSVersion.Minor -ge 2) {
            $Local:ParamsFormatted = $Local:ParamsFormatted | Join-String -Separator "`n`t";
        } else {
            $Local:ParamsFormatted = $Split -join "`n`t";
        }
        $Local:ParamsFormatted = "Parameters: $Local:ParamsFormatted";
    } else {
        [String]$Local:ParamsFormatted = 'Parameters: None';
    }
    Write-Verbose "Entered Scope`n`t$ScopeName`n`t$ParamsFormatted";
}
function Exit-Scope([Parameter(Mandatory)][System.Management.Automation.InvocationInfo]$Invocation, [Object]$ReturnValue) {
    $Invocation | Assert-NotNull -Message 'Invocation was null';
    [String]$Local:ScopeName = Get-ScopeFormatted -Invocation $Invocation;
    [String]$Local:ReturnValueFormatted = if ($null -ne $ReturnValue) {
        [String]$Local:FormattedValue = switch ($ReturnValue) {
            { $_ -is [System.Collections.Hashtable] } { "`n`t$(([HashTable]$ReturnValue).GetEnumerator().ForEach({ "$($_.Key) = $($_.Value)" }) -join "`n`t")" }
            default { $ReturnValue }
        }
        "Return Value: $Local:FormattedValue"
    } else { 'Return Value: None' };
    Write-Verbose "Exited Scope`n`t$ScopeName`n`t$ReturnValueFormatted";
}
function Get-PromptInput {
    Param(
        [Parameter(Mandatory = $true)]
        [String]$title,
        [Parameter(Mandatory = $true)]
        [String]$question
    )
    $Host.UI.RawUI.ForegroundColor = 'Yellow'
    $Host.UI.RawUI.BackgroundColor = 'Black'
    Write-Host $title
    Write-Host "$($question): " -NoNewline
    $Host.UI.RawUI.FlushInputBuffer();
    $userInput = $Host.UI.ReadLine()
    $Host.UI.RawUI.ForegroundColor = 'White'
    $Host.UI.RawUI.BackgroundColor = 'Black'
    return $userInput
}
function Prompt-Confirmation {
    Param(
        [Parameter(Mandatory = $true)]
        [String]$title,
        [Parameter(Mandatory = $true)]
        [String]$question,
        [Parameter(Mandatory = $true)]
        [bool]$defaultChoice
    )
    $DefaultChoice = if ($defaultChoice) { 0 } else { 1 }
    $Result = Prompt-Selection -title $title -question $question -choices @('&Yes', '&No') -defaultChoice $defaultChoice
    switch ($Result) {
        0 { $true }
        Default { $false }
    }
}
function Prompt-Selection {
    Param(
        [Parameter(Mandatory = $true)]
        [String]$title,
        [Parameter(Mandatory = $true)]
        [String]$question,
        [Parameter(Mandatory = $true)]
        [Array]$choices,
        [Parameter(Mandatory = $true)]
        [Int]$defaultChoice
    )
    $Host.UI.RawUI.ForegroundColor = 'Yellow'
    $Host.UI.RawUI.BackgroundColor = 'Black'
    $decision = $Host.UI.PromptForChoice($title, $question, $choices, $defaultChoice)
    $Host.UI.RawUI.ForegroundColor = 'White'
    $Host.UI.RawUI.BackgroundColor = 'Black'
    return $decision
}
function Import-DownloadableModule([String]$Name) {
    begin { Enter-Scope $MyInvocation }
    process {
        $Module = Get-Module -ListAvailable | Where-Object { $_.Name -eq $Name }
        if ($null -eq $Module) {
            Write-Host "Downloading module $Name..."
            Install-PackageProvider -Name NuGet -Confirm:$false
            Install-Module -Name $Name -Scope CurrentUser -Confirm:$false -Force
            $Module = Get-Module -ListAvailable | Where-Object { $_.Name -eq $Name }
        }
        Import-Module $Module
    }
    end { Exit-Scope $MyInvocation }
}
function Invoke-FailedExit([Parameter(Mandatory)][ValidateNotNullOrEmpty()][Int]$ExitCode, [System.Management.Automation.ErrorRecord]$ErrorRecord) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }
    process {
        If ($null -ne $ErrorRecord) {
            [System.Management.Automation.InvocationInfo]$Local:InvocationInfo = $ErrorRecord.InvocationInfo;
            $Local:InvocationInfo | Assert-NotNull -Message 'Invocation info was null, how am i meant to find error now??';
            [System.Exception]$Local:RootCause = $ErrorRecord.Exception;
            while ($null -ne $Local:RootCause.InnerException) {
                $Local:RootCause = $Local:RootCause.InnerException;
            }
            Write-Host -ForegroundColor Red $Local:InvocationInfo.PositionMessage;
            Write-Host -ForegroundColor Red $Local:RootCause.Message;
        }
        Exit $ExitCode;
    }
}
function Invoke-QuickExit {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }
    process {
        Remove-RunningFlag;
        Write-Host -ForegroundColor Red 'Exiting...';
        Exit 0;
    }
}
function Invoke-SetupEnvironment {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }
    process {
        $ErrorActionPreference = "Stop";
        # Check that the script is not running as admin
        # TODO - This will probably fail is not joined to a domain
        $curUser = [Security.Principal.WindowsIdentity]::GetCurrent().name.split('\')[1]
        if ($curUser -eq 'localadmin') {
            Write-Error "Please run this script as your normal user account, not as an administrator."
            exit 1000
        }
        # Check that all required modules are installed
        foreach ($module in @('AzureAD', 'MSOnline', 'ImportExcel')) {
            if (Get-Module -ListAvailable $module -ErrorAction SilentlyContinue) {
                Write-Host -ForegroundColor Cyan "Module $module found"
            } elseif (Prompt-Confirmation "Module $module not found" "Would you like to install it now?" $true) {
                Install-Module $module -AllowClobber -Scope CurrentUser
            } else {
                Write-Error "Module $module not found; please install it using ```nInstall-Module $module -Force``"
                exit 1001
            }
            Import-Module -Name $module
        }
        $ClientFolder = Get-ChildItem "$ClientsFolder\$Client*"
        if ($ClientFolder.Count -gt 1) {
            Write-Error "Multiple client folders found; please specify the full client name."
            exit 1003
        } elseif ($ClientFolder.Count -eq 0) {
            Write-Error "Client $Client not found; please check the spelling and try again."
            exit 1003
        } else {
            $Client = $ClientFolder | Select-Object -ExpandProperty Name
        }
        # Get the first client folder that exists
        $ReportFolder = "$ClientFolder\$ReportsFolder"
        $script:ExcelFile = "$ReportFolder\$ExcelFileName"
        if ((Test-Path $ReportFolder) -eq $false) {
            Write-Host -ForegroundColor Cyan "Report folder not found; creating $ReportFolder"
            New-Item -Path $ReportFolder -ItemType Directory | Out-Null
        }
        if (Test-Path $ExcelFile) {
            Write-Host -ForegroundColor Cyan "Excel file found; creating backup $ExcelFile.bak"
            Copy-Item -Path $ExcelFile -Destination "$ExcelFile.bak" -Force
        }
        try {
            $AzureAD = Get-AzureADCurrentSessionInfo -ErrorAction Stop
            $Continue = Prompt-Confirmation "AzureAD connection found" "It looks like you are already connected to AzureAD as $($AzureAD.Account). Would you like to continue?" $true
            if ($Continue -eq $false) { throw } else { Write-Host -ForegroundColor Cyan "Continuing with existing connection" }
        } catch {
            try {
                Connect-AzureAD -ErrorAction Stop
            } catch {
                Write-Error "Failed to connect to AzureAD"
                exit 1002
            }
        }
        try {
            $CurrentCompany = Get-MsolCompanyInformation -ErrorAction Stop | Select-Object -Property DisplayName
            $Continue = Prompt-Confirmation "MSOL connection found" "It looks like you are already connected to MSOL as $($CurrentCompany.DisplayName). Would you like to continue?" $true
            if ($Continue -eq $false) { throw } else { Write-Host -ForegroundColor Cyan "Continuing with existing connection" }
        } catch {
            try {
                Connect-MsolService -ErrorAction Stop
            } catch {
                Write-Error "Failed to connect to MSOL"
                exit 1002
            }
        }
    }
}
function Get-CurrentData {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:ExpandedUsers; }
    process {
        [Object[]]$Local:LicensedUsers = Get-MsolUser -All | Where-Object { $_.isLicensed -eq $true } | Sort-Object DisplayName;
        [PSCustomObject[]]$Local:ExpandedUsers = $Local:LicensedUsers `
            | Select-Object `
                DisplayName, `
                @{ N = 'Email'; E = { $_.UserPrincipalName } }, `
                MobilePhone, `
                @{ N = 'MFA_App'; E = { $_.StringAuthenticationPhoneAppDetails }  }, `
                @{ N = 'MFA_Email'; E = { $_.StrongAuthenticationUserDetails.Email } }, `
                @{ N = 'MFA_Phone'; E = { $_.StrongAuthenticationUserDetails.PhoneNumber } };
        return $Local:ExpandedUsers;
    }
}
function Get-Excel {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }
    process {
        $import = if (Test-Path $script:ExcelFile) {
            Write-Host -ForegroundColor Cyan "Excel file found; importing data"
            try {
                Import-Excel $script:ExcelFile
            } catch {
                Write-Error "Failed to import Excel file."
                $Message = $_.Exception.Message
                $WriteMessage = switch -Regex ($Message) {
                    "Duplicate column headers" {
                        $Match = Select-String "Duplicate column headers found on row '(?<row>[0-9]+)' in columns '(?:(?<column>[0-9]+)(?:[ ]?))+'." -InputObject $_
                        $Row = $Match.Matches.Groups[1].Captures
                        $Columns = $Match.Matches.Groups[2].Captures
                        "There were duplicate columns found on row $Row in columns $($Columns -join ", "); Please remove any duplicate columns and try again"
                    }
                    default { "Unknown error; Please examine the error message and try again" }
                }
                Write-Error $WriteMessage
                exit 1004
            }
        } else {
            Write-Host -ForegroundColor Cyan "Excel file not found; creating new file"
            New-Object -TypeName System.Collections.ArrayList
        }
        $import | Export-Excel "$script:ExcelFile" -PassThru -AutoSize -FreezeTopRowFirstColumn
    }
}
function Get-EmailToCell([Parameter(Mandatory)][ValidateNotNullOrEmpty()][OfficeOpenXml.ExcelWorksheet]$WorkSheet) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:EmailTable; }
    process {
        Trap {
            Write-Host -ForegroundColor Red "Unexpected error occurred while getting email to cell mapping";
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        };
        [Int]$Local:SheetRows = $WorkSheet.Dimension.Rows;
        # If null or less than 2 rows, there is no pre-existing data.
        If ($null -eq $Local:SheetRows -or $Local:SheetRows -lt 2) {
            Write-Host -ForegroundColor Cyan "No data found in worksheet $($WorkSheet.Name)";
            return @{};
        }
        [HashTable]$Local:EmailTable = @{};
        [Int]$Local:ColumnIndex = 2;
        foreach ($Local:Row in 2..$Local:SheetRows) {
            [String]$Local:Email = $WorkSheet.Cells[$Local:Row, $Local:ColumnIndex].Value;
            $Local:Email | Assert-NotNull -Message "Email was null";
            $Local:EmailTable.Add($Local:Email, $Local:Row);
        }
        return $Local:EmailTable;
    }
}
function Update-History([OfficeOpenXml.ExcelWorksheet]$ActiveWorkSheet, [OfficeOpenXml.ExcelWorksheet]$HistoryWorkSheet, [int]$KeepHistory = 4) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }
    process {
        # This is a new worksheet, no history to update
        if ($ActiveWorkSheet.Dimension.Columns -lt 4) {
            Write-Host -ForegroundColor Cyan "No data found in worksheet $($ActiveWorkSheet.Name), skipping history update."
            return
        }
        $TotalColumns = $ActiveWorkSheet.Dimension.Columns
        $RemovedColumns = 0
        $KeptRange = ($TotalColumns - $KeepHistory)..$TotalColumns
        foreach ($ColumnIndex in 4..$ActiveWorkSheet.Dimension.Columns) {
            $WillKeep = $KeptRange -contains $ColumnIndex
            $ColumnIndex = $ColumnIndex - $RemovedColumns
            $DateValue = $ActiveWorkSheet.Cells[1, $ColumnIndex].Value
            Write-Host -ForegroundColor Cyan "Processing Column $ColumnIndex which is dated $DateValue, moving to history: $(!$WillKeep)"
            # Empty column, remove and continue;
            if ($null -eq $DateValue -or $DateValue -eq '') {
                $ActiveWorkSheet.DeleteColumn($ColumnIndex)
                $RemovedColumns++
                continue
            }
            # This is absolutely fucking revolting
            $Date = try {
                Get-Date -Date ($DateValue)
            } catch {
                try {
                    Get-Date -Date "$($DateValue)-$(Get-Date -Format 'yyyy')"
                } catch {
                    try {
                        [DateTime]::FromOADate($DateValue)
                    } catch {
                        Write-Host -ForegroundColor Cyan "Deleting what is thought to be invalid or check column at $ColumnIndex"
                        # Probably the check column, remove and continue;
                        $ActiveWorkSheet.DeleteColumn($ColumnIndex)
                        $RemovedColumns++
                        continue
                    }
                }
            }
            Write-Host -ForegroundColor Cyan "Processing Column $ColumnIndex which is dated $Date, moving to history: $(!$WillKeep)"
            if ($WillKeep -eq $true) {
                continue
            }
            if ($null -ne $HistoryWorkSheet) {
                $HistoryColumnIndex = $HistoryWorkSheet.Dimension.Columns + 1
                Write-Host -ForegroundColor Cyan "Moving column $ColumnIndex from working page into history page at $HistoryColumnIndex"
                $HistoryWorkSheet.InsertColumn($HistoryColumnIndex, 1)
                $HistoryWorkSheet.Cells[1, $HistoryColumnIndex].Value = $Date.ToString('MMM-yy')
                $HistoryEmails = Get-EmailToCell -WorkSheet $HistoryWorkSheet
                foreach ($RowIndex in 2..$ActiveWorkSheet.Dimension.Rows) {
                    Write-Host -ForegroundColor Cyan "Processing row $RowIndex"
                    $Email = $ActiveWorkSheet.Cells[$RowIndex, 2].Value
                    $HistoryIndex = $HistoryEmails[$Email]
                    if ($null -eq $HistoryIndex) {
                        $HistoryIndex = $HistoryWorkSheet.Dimension.Rows + 1
                        $HistoryWorkSheet.InsertRow($HistoryIndex, 1)
                        $HistoryWorkSheet.Cells[$HistoryIndex, 2].Value = $Email
                    } else {
                        # Update the name and phone number
                        $HistoryWorkSheet.Cells[$HistoryIndex, 1].Value = $ActiveWorkSheet.Cells[$RowIndex, 1].Value
                        $HistoryWorkSheet.Cells[$HistoryIndex, 3].Value = $ActiveWorkSheet.Cells[$RowIndex, 3].Value
                    }
                    $HistoryWorkSheet.Cells[$HistoryIndex, $HistoryColumnIndex].Value = $ActiveWorkSheet.Cells[$RowIndex, $ColumnIndex].Value
                }
            }
            $ActiveWorkSheet.DeleteColumn($ColumnIndex)
            $RemovedColumns++
        }
    }
}
function Get-ColumnDate {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [OfficeOpenXml.ExcelWorksheet]$WorkSheet,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Int32]$ColumnIndex
    )
    $DateValue = $WorkSheet.Cells[1, $ColumnIndex].Value
    try {
        Get-Date -Date ($DateValue)
    } catch {
        $Date = [DateTime]::FromOADate($DateValue)
        if ($Date.Year -eq 1899 -and $Date.Month -eq 12 -and $Date.Day -eq 30) {
            $null
        } else {
            $Date
        }
    }
}
function Invoke-CleanupWorksheet(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [OfficeOpenXml.ExcelWorksheet]$WorkSheet,
    [switch]$DuplicateCheck
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }
    process {
        $Rows = $WorkSheet.Dimension.Rows
        if ($null -ne $Rows -and $Rows -ge 2) {
            # Start from 2 because the first row is the header
            $RemovedRows = 0
            $VisitiedEmails = New-Object System.Collections.Generic.List[String]
            foreach ($RowIndex in 2..$WorkSheet.Dimension.Rows) {
                $RowIndex = $RowIndex - $RemovedRows
                $Email = $WorkSheet.Cells[$RowIndex, 2].Value
                Write-Host -ForegroundColor Cyan "Processing row $RowIndex with email '$Email'"
                # Remove any empty rows between actual data
                if ($null -eq $Email) {
                    Write-Host -ForegroundColor Cyan "Removing row $RowIndex because email is empty."
                    $WorkSheet.DeleteRow($RowIndex)
                    $RemovedRows++
                    continue
                }
                if ($DuplicateCheck) {
                    Write-Host -ForegroundColor Cyan "Checking for duplicate email '$Email'"
                    if (!$VisitiedEmails.Contains($Email)) {
                        Write-Host -ForegroundColor Cyan "Adding email '$Email' to the list of visited emails"
                        $VisitiedEmails.Add($Email)
                        continue
                    }
                    Write-Host -ForegroundColor Cyan "Duplicate email '$Email' found at virtual row $RowIndex (Offset by $($RemovedRows + 2))"
                    $AdditionalRealIndex = $RowIndex + $RemovedRows
                    $ExistingRealIndex = $VisitiedEmails.IndexOf($Email) + 2 + $RemovedRows
                    $Question = "Duplicate email found at row $AdditionalRealIndex`nThe email '$Email' was first seen at row $ExistingRealIndex.`nPlease select which row you would like to keep, or enter 'b' to break and manually review the file."
                    $Selection = Prompt-Selection "Duplicate Email" $Question @("&Existing", "&New", "&Break") 0
                    $RemovingRow = switch ($Selection) {
                        0 { $RowIndex }
                        1 {
                            $ExistingIndex = $VisitiedEmails.IndexOf($Email)
                            $VisitiedEmails.Remove($Email)
                            $VisitiedEmails.Add($Email)
                            $ExistingIndex
                        }
                        default {
                            Write-Error "Please manually review and remove the duplicate email that exists at rows $ExistingRealIndex and $AdditionalRealIndex"
                            Exit 1010
                        }
                    }
                    Write-Host -ForegroundColor Cyan "Removing row $RemovingRow "
                    $WorkSheet.DeleteRow($RemovingRow)
                    $RemovedRows++
                }
            }
        }
        $Columns = $WorkSheet.Dimension.Columns
        if ($null -ne $Columns -and $Columns -ge 4) {
            # Start from 4 because the first three columns are name,email,phone
            $RemovedColumns = 0
            foreach ($ColumnIndex in 4..$WorkSheet.Dimension.Columns) {
                $ColumnIndex = $ColumnIndex - $RemovedColumns
                # Remove any empty columns, or invalid date columns between actual data
                # TODO -> Use Get-ColumnDate
                $Value = $WorkSheet.Cells[1, $ColumnIndex].Value
                if ($null -eq $Value -or $Value -eq 'Check') {
                    Write-Host -ForegroundColor Cyan "Removing column $ColumnIndex because date is empty or invalid."
                    $WorkSheet.DeleteColumn($ColumnIndex)
                    $RemovedColumns++
                    continue
                }
            }
        }
    }
}
function Remove-Users([PSCustomObject[]]$NewData, [OfficeOpenXml.ExcelWorksheet]$WorkSheet) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }
    process {
        Trap {
            Write-Host -ForegroundColor Red "Unexpected error occurred while removing users from worksheet";
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        };
        [HashTable]$Local:EmailTable = Get-EmailToCell -WorkSheet $WorkSheet;
        $Local:EmailTable | Assert-NotNull -Message 'Email table was null';
        # Sort decenting by value, so that we can remove from the bottom up without affecting the index.
        [HashTable]$Local:EmailTable = $Local:EmailTable | Sort-Object -Property Values -Descending;
        $Local:EmailTable | ForEach-Object {
            [String]$Local:ExistingEmail = $_.Name;
            [Int]$Local:ExistingRow = $_.Value;
            # Find the object in the new data which matches the existing email.
            [String]$Local:NewData = $NewData | Where-Object { $_.Email -eq $Local:ExistingEmail } | Select-Object -First 1;
            If ($null -eq $Local:NewData) {
                Write-Host -ForegroundColor Cyan -Object "$Local:ExistingEmail is not longer present in the new data, removing from row $Local:ExistingRow";
                $WorkSheet.DeleteRow($Local:ExistingRow);
            }
        }
    }
}
function Add-Users([PSCustomObject[]]$NewData, [OfficeOpenXml.ExcelWorksheet]$WorkSheet) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }
    process {
        Trap {
            Write-Host -ForegroundColor Red "Unexpected error occurred while adding users to worksheet";
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        };
        [HashTable]$Local:EmailTable = Get-EmailToCell -WorkSheet $WorkSheet;
        $Local:EmailTable | Assert-NotNull -Message 'Email table was null';
        [PSCustomObject]$Local:NewUsers = $NewData | Where-Object { -not $Local:EmailTable.ContainsKey($_.Email) };
        If ($null -eq $Local:NewUsers) {
            Write-Host -ForegroundColor Cyan -Object "No new users found, skipping add users.";
            return;
        }
        # Create a new Email table, but this time with the insertions of users
        # Each value is a boolean which is only true if they are a new user.
        # This should be sorted by displayName, so that we can insert them in the correct order.
        [HashTable]$Local:TableWithInsertions = @{};
        $Local:EmailTable.GetEnumerator().ForEach({$Local:TableWithInsertions.Add($_.Key, $false); });
        $Local:NewUsers | ForEach-Object { $Local:TableWithInsertions.Add($_.Email, $true); };
        [Object[]]$Local:TableWithInsertions = $Local:TableWithInsertions.GetEnumerator() | Sort-Object -Property Key;
        [Int]$Local:LastRow = 1;
        $Local:TableWithInsertions | ForEach-Object {
            $Local:LastRow++;
            [String]$Local:Email = $_.Key;
            [Boolean]$Local:IsNewUser = $_.Value;
            If ($Local:IsNewUser) {
                Write-Host -ForegroundColor Cyan -Object "$Local:Email is a new user, inserting into row $($Local:LastRow + 1)";
                [PSCustomObject]$Local:NewUserData = $NewData | Where-Object { $_.Email -eq $Local:Email } | Select-Object -First 1;
                # $Local:NewUserData | Assert-NotNull -Message 'New user data was null';
                $WorkSheet.InsertRow($Local:LastRow, 1);
                $WorkSheet.Cells[$Local:LastRow, 1].Value = $Local:NewUserData.DisplayName;
                $WorkSheet.Cells[$Local:LastRow, 2].Value = $Local:NewUserData.Email;
                $WorkSheet.Cells[$Local:LastRow, 3].Value = $Local:NewUserData.MobilePhone;
            }
        }
    }
}
function Invoke-OrderUsers(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [OfficeOpenXml.ExcelWorksheet]$WorkSheet
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }
    process {
        Trap {
            Write-Host -ForegroundColor Red "Unexpected error occurred while re-ordering users";
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        };
        return
        [HashTable]$Local:EmailTable = Get-EmailToCell -WorkSheet $WorkSheet;
        [HashTable]$Local:RequiresSorting = @{};
        foreach ($Local:Index in $Local:EmailTable.Values) {
            [String]$Local:DisplayName = $WorkSheet.Cells[$Local:Index, 1].Value;
            $Local:RequiresSorting.Add($Local:DisplayName, $Local:Index);
        }
        $Local:RequiresSorting | Assert-NotNull -Message 'Requires sorting was null';
        [Int]$Local:SortedRows = 0;
        while ($Local:RequiresSorting.Count -gt 0) {
            [String]$Local:SmallestKey = $Local:RequiresSorting.Keys[0];
            foreach ($Local:Key in $Local:RequiresSorting.Keys) {
                If ($Local:Key -lt $Local:SmallestKey) {
                    $Local:SmallestKey = $Local:Key;
                }
            }
            Write-Host -ForegroundColor Cyan -Object "Smallest key is $Local:SmallestKey";
            [Int]$Local:CurrentIndex = $Local:RequiresSorting[$Local:SmallestKey];
            [Int]$Local:ShouldBeAt = $Local:SortedRows++ + 2;
            If ($Local:CurrentIndex -ne $Local:ShouldBeAt) {
                Write-Host -ForegroundColor Cyan -Object "Moving row $Local:CurrentIndex to row $Local:ShouldBeAt";
                $WorkSheet.InsertRow($Local:ShouldBeAt, 1);
                foreach ($Local:Column in (1..$WorkSheet.Dimension.Columns)) {
                    $Local:Value = $WorkSheet.Cells[$Local:CurrentIndex, $Local:Column].Text;
                    $WorkSheet.Cells[$Local:ShouldBeAt, $Local:Column].Value = $Local:Value;
                }
                $WorkSheet.DeleteRow($Local:CurrentIndex);
                foreach ($Local:Key in $Local:RequiresSorting.Clone().Keys) {
                    [Int]$Local:Value = $Local:RequiresSorting[$Local:Key];
                    If ($Local:Value -lt $Local:CurrentIndex) {
                        $Local:RequiresSorting[$Local:Key] = $Local:Value + 1;
                    }
                }
            }
            $Local:RequiresSorting.Remove($Local:SmallestKey);
        }
    }
}
function Update-Data([PSCustomObject[]]$NewData, [OfficeOpenXml.ExcelWorksheet]$WorkSheet, [switch]$AddNewData) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }
    process {
        Trap {
            Write-Host -ForegroundColor Red "Unexpected error occurred while updating data";
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        };
        # We have already re-ordered, and inserted new users, so now we just need to add a new column for the current month.
        [HashTable]$Local:EmailTable = Get-EmailToCell -WorkSheet $WorkSheet;
        $Local:EmailTable | Assert-NotNull -Message 'Email table was null';
        # Only insert new column if required.
        If ($AddNewData) {
            [String]$Local:NewColumnName = Get-Date -Format "MMM-yy";
            [Int]$Local:NewColumnIndex = [Math]::Max(3, $WorkSheet.Dimension.Columns + 1);
            $WorkSheet.Cells[1, $Local:NewColumnIndex].Value = $Local:NewColumnName;
        }
        foreach ($Local:User in $NewData) {
            [String]$Local:Email = $Local:User.Email;
            [Int]$Local:Row = $Local:EmailTable[$Local:Email];
            if ($null -eq $Local:Row -or $Local:Row -eq 0) {
                Write-Host -ForegroundColor Cyan -Object "$Local:Email doesn't exist in this sheet yet, skipping.";
                continue;
            }
            Write-Host -ForegroundColor Cyan -Object "Updating row $Local:Row with new data";
            $WorkSheet.Cells[$Local:Row, 1].Value = $Local:User.DisplayName;
            $WorkSheet.Cells[$Local:Row, 2].Value = $Local:User.Email;
            $WorkSheet.Cells[$Local:Row, 3].Value = $Local:User.MobilePhone;
            If ($AddNewData) {
                $Local:Cell = $WorkSheet.Cells[$Local:Row, $Local:NewColumnIndex];
                $Local:Cell.Value = $Local:User.MFA_Phone;
                $Local:Cell.Style.Numberformat.Format = "@";
                $Local:Cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::None;
            }
        }
    }
}
function Set-Check(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [OfficeOpenXml.ExcelWorksheet]$WorkSheet
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }
    process {
        $Cells = $WorkSheet.Cells
        $lastColumn = $WorkSheet.Dimension.Columns
        $prevColumn = $lastColumn - 1
        $currColumn = $lastColumn
        $checkColumn = $lastColumn + 1
        if ($WorkSheet.Dimension.Columns -eq 4) {
            $prevColumn = $lastColumn + 2
        }
        foreach ($row in 2..$WorkSheet.Dimension.Rows) {
            $prevNumber = $Cells[$row, $prevColumn].Value
            $currNumber = $Cells[$row, $currColumn].Value
            $Cell = $Cells[$row, $checkColumn]
            ($Result, $Colour) = if ([String]::IsNullOrWhitespace($prevNumber) -and [String]::IsNullOrWhitespace($currNumber)) {
                'Missing',[System.Drawing.Color]::Turquoise
            } elseif ([String]::IsNullOrWhitespace($prevNumber)) {
                'No Previous',[System.Drawing.Color]::Yellow
            } elseif ($prevNumber -eq $currNumber) {
                'Match',[System.Drawing.Color]::Green
            } else {
                'Miss-match',[System.Drawing.Color]::Red
            }
            Write-Host -ForegroundColor Cyan "Setting cell $row,$checkColumn to $colour"
            $Cell.Value = $Result
            $Cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
            $Cell.Style.Fill.BackgroundColor.SetColor(($Colour))
        }
        $Cells[1, $checkColumn].Value = 'Check'
    }
}
function Set-Styles(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [OfficeOpenXml.ExcelWorksheet]$WorkSheet
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }
    process {
        $lastColumn = $WorkSheet.Dimension.Address -split ':' | Select-Object -Last 1
        $lastColumn = $lastColumn -replace '[0-9]', ''
        Set-ExcelRange -Worksheet $WorkSheet -Range "A1:$($lastColumn)1" -Bold -HorizontalAlignment Center
        if ($WorkSheet.Dimension.Columns -ge 4) { Set-ExcelRange -Worksheet $WorkSheet -Range "D1:$($lastColumn)1" -NumberFormat "MMM-yy" }
        Set-ExcelRange -Worksheet $WorkSheet -Range "A2:$($lastColumn)$(($WorkSheet.Dimension.Rows))" -AutoSize -ResetFont -BackgroundPattern Solid
        # Set-ExcelRange -Worksheet $WorkSheet -Range "A2:$($lastColumn)$($WorkSheet.Dimension.Rows)"  # [System.Drawing.Color]::LightSlateGray
        # Set-ExcelRange -Worksheet $WorkSheet -Range "D2:$($lastColumn)$($WorkSheet.Dimension.Rows)" -NumberFormat "[<=9999999999]####-###-###;+(##) ###-###-###"
    }
}
function New-BaseWorkSheet([Parameter(Mandatory)][ValidateNotNullOrEmpty()][OfficeOpenXml.ExcelWorksheet]$WorkSheet) {
    # Test if the worksheet has data by checking the dimension
    # If the dimension is null then there is no data
    if ($null -ne $WorkSheet.Dimension) {
        return
    }
    $WorkSheet.InsertColumn(1, 3)
    $WorkSheet.InsertRow(1, 1)
    $Local:Cells = $WorkSheet.Cells
    $Local:Cells[1, 1].Value = "Name"
    $Local:Cells[1, 2].Value = "Email"
    $Local:Cells[1, 3].Value = "Phone"
}
function Get-ActiveWorkSheet(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [OfficeOpenXml.ExcelPackage]$ExcelData
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:ActiveWorkSheet; }
    process {
        [OfficeOpenXml.ExcelWorksheet]$Local:ActiveWorkSheet = $ExcelData.Workbook.Worksheets | Where-Object { $_.Name -eq 'Working' };
        if ($null -eq $Local:ActiveWorkSheet) {
            [OfficeOpenXml.ExcelWorksheet]$Local:ActiveWorkSheet = $ExcelData.Workbook.Worksheets.Add('Working')
        } else { $Local:ActiveWorkSheet.Name = "Working" }
        # Move the worksheets to the correct position
        $ExcelData.Workbook.Worksheets.MoveToStart("Working")
        New-BaseWorkSheet -WorkSheet $Local:ActiveWorkSheet;
        return $Local:ActiveWorkSheet;
    }
}
function Get-HistoryWorkSheet(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [OfficeOpenXml.ExcelPackage]$ExcelData
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:HistoryWorkSheet; }
    process {
        [OfficeOpenXml.ExcelWorksheet]$Local:HistoryWorkSheet = $ExcelData.Workbook.Worksheets[2]
        if ($null -eq $HistoryWorkSheet -or $HistoryWorkSheet.Name -ne "History") {
            Write-Host -ForegroundColor Cyan "Creating new worksheet for history"
            $HistoryWorkSheet = $ExcelData.Workbook.Worksheets.Add("History")
        }
        # Move the worksheets to the correct position
        $ExcelData.Workbook.Worksheets.MoveAfter("History", "Working")
        New-BaseWorkSheet -WorkSheet $Local:HistoryWorkSheet;
        return $Local:HistoryWorkSheet;
    }
}
function Save-Excel([OfficeOpenXml.ExcelPackage]$ExcelData) {
    begin { Enter-Scope $MyInvocation }
    process {
        if ($ExcelData.Workbook.Worksheets.Count -gt 2) {
            Write-Host -ForegroundColor Cyan "Removing $($ExcelData.Workbook.Worksheets.Count - 2) worksheets"
            foreach ($Index in 3..$ExcelData.Workbook.Worksheets.Count) {
                $ExcelData.Workbook.Worksheets.Delete(3)
            }
        }
        Close-ExcelPackage $ExcelData -Show #-SaveAs "$ExcelFile.new.xlsx"
    }
    end { Exit-Scope $MyInvocation }
}
function Main {
    begin { Enter-Scope -Invocation $MyInvocation; }
    process {
        Trap {
            Write-Host -ForegroundColor Red "Unexpected error occurred while running main";
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        };
        Invoke-SetupEnvironment;
        [PSCustomObject[]]$Local:NewData = Get-CurrentData;
        [OfficeOpenXml.ExcelPackage]$Local:ExcelData = Get-Excel;
        [OfficeOpenXml.ExcelWorksheet]$Local:ActiveWorkSheet = Get-ActiveWorkSheet -ExcelData $Local:ExcelData;
        [OfficeOpenXml.ExcelWorksheet]$Local:HistoryWorkSheet = Get-HistoryWorkSheet -ExcelData $Local:ExcelData;
        $Local:ActiveWorkSheet | Assert-NotNull -Message 'ActiveWorkSheet was null';
        $Local:HistoryWorkSheet | Assert-NotNull -Message 'HistoryWorkSheet was null';
        Invoke-CleanupWorksheet -WorkSheet $Local:ActiveWorkSheet -DuplicateCheck;
        Invoke-CleanupWorksheet -WorkSheet $Local:HistoryWorkSheet;
        Update-History -HistoryWorkSheet $Local:HistoryWorkSheet -ActiveWorkSheet $Local:ActiveWorkSheet;
        Remove-Users -NewData $Local:NewData -WorkSheet $Local:ActiveWorkSheet;
        Add-Users -NewData $Local:NewData -WorkSheet $Local:ActiveWorkSheet;
        Update-Data -NewData $Local:NewData -WorkSheet $Local:ActiveWorkSheet -AddNewData;
        Update-Data -NewData $Local:NewData -WorkSheet $Local:HistoryWorkSheet;
        Invoke-OrderUsers -WorkSheet $Local:ActiveWorkSheet;
        Invoke-OrderUsers -WorkSheet $Local:HistoryWorkSheet;
        Set-Check -WorkSheet $Local:ActiveWorkSheet
        @($Local:ActiveWorkSheet, $Local:HistoryWorkSheet) | ForEach-Object { Set-Styles -WorkSheet $_ }
        Save-Excel -ExcelData $Local:ExcelData
    }
    end { Exit-Scope $MyInvocation }
}
Main

