#Requires -Version 5.1
#Requires -Modules AzureADPreview ExchangeOnlineManagement Microsoft.Online.SharePoint.PowerShell MSOnline

Param(
    [Parameter(Mandatory)]
    [ValidateSet("SecurityAlerts", "ConditionalAccess", "Sharepoint", "Exchange")]
    [String]$Action
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
function Set-Sharepoint_SharingDomains {
    Connect-Service -Service AzureAD;
    Set-SPOTenant -SharingDomainRestrictionMode AllowList -SharingAllowedDomainList ((Get-AzureADDomain | Select-Object -ExpandProperty Name) -join ' ')
}
function Disable-Outlook_StorageProviders {
    Connect-Service -Service ExchangeOnline;
    Set-OwaMailboxPolicy -Identity OwaMailboxPolicy-Default -AdditionalStorageProvidersAvailable $false
}
function Get-AlertsUser {
    $User = (Get-User | Where-Object { $_.Name -like 'Alerts*' } | Select-Object -First 1)
    if ($User) {
        return $User
    } else {
        # TODO :: Auto-create with memorable-pass
        Write-Warning "No Alerts user found. Please create one manually."
        return $null
        # $params = @{
        #     Name             = "Alerts"
        #     DisplayName      = "Alerts"
        #     UserPrincipalName = "Alerts@$(Get-OrganizationConfig).PrimarySmtpAddress.Domain"
        #     FirstName        = "Alerts"
        #     LastName         = "Alerts"
        #     Password         = (ConvertTo-SecureString -String "P@ssw0rd" -AsPlainText -Force)
        #     ResetPasswordOnNextLogon = $false
        #     PasswordNeverExpires    = $true
        #     UsageLocation           = "US"
        #     ForceChangePasswordNextLogon = $false
        # }
        # New-User @params
    }
}
function Set-SecurityAndCompilenceAlerts([PSObject]$AlertsUser) {
    $Alerts = Get-ProtectionAlert
    $AlertNames = $Alerts | Select-Object -ExpandProperty Name
    $Alerts = $Alerts | Where-Object { ($_.NotifyUser -ne $AlertsUser.WindowsLiveID) -and !$_.Disabled }
    if ($null -eq $Alerts -or $Alerts.Count -eq 0) {
        Write-Host "All Security and Complience alerts are already configured to notify the Alerts user."
        return
    }
    $UnableToCreate = @()
    foreach ($Alert in $Alerts) {
        if ($Alert.IsSystemRule) {
            # Check for existing custom rule
            if ($AlertNames -contains "AMT $($Alert.Name)") {
                Write-Host "Custom alert already exists for $($Alert.Name). Skipping..."
                continue
            }
            # We need to re-create this as a custom rule so we can modify the NotifyUser property
            $NewAlert = $Alert | Select-Object -Property * | ForEach-Object {
                $_.Name = "AMT $($_.Name)"
                $_.NotifyUser = $AlertsUser.WindowsLiveID
                $_
            }
            try {
                New-ProtectionAlert -AggregationType $NewAlert.AggregationType -AlertBy $NewAlert.AlertBy -AlertFor $NewAlert.AlertFor -Category $NewAlert.Category -Comment $NewAlert.Comment -CorrelationPolicyId $NewAlert.CorrelationPolicyId -CustomProperties $NewAlert.CustomProperties -Description $NewAlert.Description -Disabled $NewAlert.Disabled -Filter $NewAlert.Filter -LogicalOperationName $NewAlert.LogicalOperationName -Name $NewAlert.Name -NotificationCulture $NewAlert.NotificationCulture -NotificationEnabled $NewAlert.NotificationEnabled -NotifyUser $NewAlert.NotifyUser -NotifyUserOnFilterMatch $NewAlert.NotifyUserOnFilterMatch -NotifyUserSuppressionExpiryDate $NewAlert.NotifyUserSuppressionExpiryDate -NotifyUserThrottleThreshold $NewAlert.NotifyUserThrottleThreshold -NotifyUserThrottleWindow $NewAlert.NotifyUserThrottleWindow -Operation $NewAlert.Operation -PrivacyManagementScopedSensitiveInformationTypes $NewAlert.PrivacyManagementScopedSensitiveInformationTypes -PrivacyManagementScopedSensitiveInformationTypesForCounting $NewAlert.PrivacyManagementScopedSensitiveInformationTypesForCounting -PrivacyManagementScopedSensitiveInformationTypesThreshold $NewAlert.PrivacyManagementScopedSensitiveInformationTypesThreshold -Severity $NewAlert.Severity -ThreatType $NewAlert.ThreatType -Threshold $NewAlert.Threshold -TimeWindow $NewAlert.TimeWindow -UseCreatedDateTime $NewAlert.UseCreatedDateTime -VolumeThreshold $NewAlert.VolumeThreshold -ErrorAction Stop | Out-Null
                $AlertNames += $NewAlert.Name
            } catch {
                Write-Warning "Unable to create custom alert for $($Alert.Name)."
                $UnableToCreate += $Alert.Name
            }
        }
        else {
            Set-ProtectionAlert -Identity $Alert.Name -NotifyUser $AlertsUser.WindowsLiveID | Out-Null
        }
    }
    if ($UnableToCreate.Count -gt 0) {
        Write-Warning "Unable to create custom alerts for the following alerts: $($UnableToCreate -join ', ')"
        Write-Warning "Please update these alerts manually at ``https://security.microsoft.com/alertpoliciesv2`` for alerts user ``$($AlertsUser.UserPrincipalName)``."
    }
}
function New-ConditionalAccessPrivilegedIdentityManagementPolicy {
    Connect-Service AzureAD;
    #region - Const Variables
    $Local:PolicyName = "Privileged Identity Managementt"
    $Local:DirectoryRoles = @("Application administrator", "Authentication administrator", "Billing administrator", "Cloud application administrator", "Conditional Access administrator", "Exchange administrator", "Global administrator", "Global reader", "Helpdesk administrator", "Password administrator", "Privileged authentication administrator", "Privileged role administrator", "Security administrator", "SharePoint administrator", "User administrator")
    #endregion
    $Local:ExistingPolicy = Get-AzureADMSConditionalAccessPolicy | Where-Object { $_.DisplayName -eq $Local:PolicyName }
    # TODO :: Check if policy is configured correctly
    if ($Local:ExistingPolicy) {
        Write-Host "Privileged Identity Management policy already exists. Skipping..."
        return
    }
    [Microsoft.Open.MSGraph.Model.ConditionalAccessConditionSet]$Local:Conditions = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessConditionSet
    # Apply to all cloud applications
    $Local:Conditions.Applications = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessApplicationCondition
    $Local:Conditions.Applications.IncludeApplications = "All"
    # Apply to administator roles
    $Local:Conditions.Users = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessUserCondition
    $Local:Conditions.Users.IncludeRoles = Get-AzureADMSRoleDefinition | Where-Object { $Local:DirectoryRoles -contains $_.DisplayName } | Select-Object -ExpandProperty Id
    [Microsoft.Open.MSGraph.Model.ConditionalAccessGrantControls]$Local:GrantControls = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessGrantControls
    # Enforce MFA
    $Local:GrantControls._Operator = "OR"
    $Local:GrantControls.BuiltInControls = @("mfa")
    [Microsoft.Open.MSGraph.Model.ConditionalAccessSessionControls]$Local:SessionControls = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessSessionControls
    # Disable persistent browser
    $Local:SessionControls.PersistentBrowser = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessPersistentBrowser
    $Local:SessionControls.PersistentBrowser.IsEnabled = $true
    $Local:SessionControls.PersistentBrowser.Mode = "Never"
    # Require Re-authentication every 4 hours
    $Local:SessionControls.SignInFrequency = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessSignInFrequency
    $Local:SessionControls.SignInFrequency.IsEnabled = $true
    $Local:SessionControls.SignInFrequency.Value = "4"
    $Local:SessionControls.SignInFrequency.Type = "hours"
    New-AzureADMSConditionalAccessPolicy -DisplayName $Local:PolicyName -State "Enabled" -Conditions $Local:Conditions -GrantControls $Local:GrantControls -SessionControls $Local:SessionControls -ErrorAction Stop | Out-Null
}

(New-Module -ScriptBlock $Global:EmbededModules['Environment.psm1'] -AsCustomObject -ArgumentList $MyInvocation.BoundParameters).'Invoke-RunMain'($MyInvocation, {
    switch ($Action) {
        'SecurityAlerts' {
            $AlertsUser = Get-AlertsUser
            if ($AlertsUser) {
                $Continue = $Host.UI.PromptForChoice("Alerts User: $($AlertsUser.WindowsLiveID)", 'Is this the correct alerts user?', @('&Yes', '&No'), 0)
                if ($Continue -eq 1) {
                    Write-Host "Please update the alerts user manually at ``https://admin.microsoft.com/Adminportal/Home#/users``."
                    exit 1003
                }
                Set-SecurityAndCompilenceAlerts -AlertsUser $AlertsUser
            }
        }
        'ConditionalAccess' {
            New-ConditionalAccessPrivilegedIdentityManagementPolicy;
        }
        'Sharepoint' {
        }
        'Exchange' {
            Disable-Outlook_StorageProviders
            Set-Exchange_SafeAttachmentsPolicy
            Set-Exchange_SafeLinksPolicy
            Enable-Exchange_MailboxAuditing
            Enable-Exchange_MailTips
        }
    }
});
