#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
Param (
    [Parameter()]
    [ValidateSet("Configure", "Cleanup", "Install", "Update", "Finish")]
    [String]$Phase = "Configure",
    [Parameter(DontShow)]
    [ValidateLength(32, 32)]
    [Parameter(DontShow)]
    [ValidateNotNullOrEmpty()]
    [String]$Endpoint = "system-monitor.com",
    [Parameter(DontShow)]
    [ValidateNotNullOrEmpty()]
    [String]$NetworkName = "Guests",
    [Parameter(DontShow)]
    [ValidateNotNullOrEmpty()]
    [Parameter(DontShow)]
    [ValidateNotNullOrEmpty()]
    [String]$TaskName = "SetupScheduledTask",
    [Parameter(DontShow)]
    [ValidateNotNullOrEmpty()]
    [Int]$RecursionLevel = 0
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
		function Invoke-Write {
		    [CmdletBinding(PositionalBinding)]
		    param (
		        [Parameter(ParameterSetName = 'InputObject', ValueFromPipeline)]
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
		        [Boolean]$ShouldWrite = $True,
		        [Parameter(ParameterSetName = 'Splat', ValueFromPipelineByPropertyName)]
		        [ValidateNotNullOrEmpty()]
		        [Switch]$NoNewLine
		    )
		    process {
		        if ($InputObject) {
		            Invoke-Write @InputObject;
		            return;
		        }
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
        [String]$Script:PackageManager = switch ($env:OS) {
		    'Windows_NT' { "choco" };
		    default {
		        throw "Unsupported operating system.";
		    };
		};
		[HashTable]$Script:PackageManager = switch ($Script:PackageManager) {
		    "choco" {
		        [String]$Local:ChocolateyPath = "$($env:SystemDrive)\ProgramData\Chocolatey\bin\choco.exe";
		        if (Test-Path -Path $Local:ChocolateyPath) {
		            # Ensure Chocolatey is usable.
		            Import-Module "$($env:SystemDrive)\ProgramData\Chocolatey\Helpers\chocolateyProfile.psm1" -Force;
		            refreshenv | Out-Null;
		        } else {
		            throw 'Chocolatey is not installed on this system.';
		        }
		        @{
		            Executable = $Local:ChocolateyPath;
		            Commands = @{
		                List       = 'list';
		                Uninstall  = 'uninstall';
		                Install    = 'install';
		                Update     = 'upgrade';
		            }
		            Options = @{
		                Common = @('--confirm', '--limit-output', '--exact');
		                Force = '--force';
		            }
		        };
		    };
		    default {
		        throw "Unsupported package manager.";
		    };
		};
		function Test-Package(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [String]$PackageName
		    # [Parameter()]
		    # [ValidateNotNullOrEmpty()]
		    # [String]$PackageVersion
		) {
		    $Local:Params = @{
		        PSPrefix = '🔍';
		        PSMessage = "Checking if package '$PackageName' is installed...";
		        PSColour = 'Yellow';
		    };
		    Invoke-Write @Local:Params;
		    # if ($PackageVersion) {
		    #     $Local:PackageArgs['Version'] = $PackageVersion;
		    # }
		    # TODO :: Actually get the return value.
		    & $Script:PackageManager.Executable $Script:PackageManager.Commands.List $Script:PackageManager.Options.Common $PackageName;
		}
		function Install-ManagedPackage(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [String]$PackageName
		    # [Parameter()]
		    # [ValidateNotNullOrEmpty()]
		    # [String]$PackageVersion
		) {
		    @{
		        PSPrefix = '📦';
		        PSMessage = "Installing package '$PackageName'...";
		        PSColour = 'Green';
		    } | Invoke-Write;
		    # if ($PackageVersion) {
		    #     $Local:PackageArgs['Version'] = $PackageVersion;
		    # }
		    # TODO :: Ensure success.
		    & $Script:PackageManager.Executable $Script:PackageManager.Commands.Install $Script:PackageManager.Options.Common $PackageName;
		}
		function Uninstall-Package() {
		}
		function Update-Package() {
		}
		Export-ModuleMember -Function Test-Package, Install-ManagedPackage, Uninstall-Package, Update-Package;
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
	"99-Registry.psm1" = {
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
	"99-UsersAndAccounts.psm1" = {
        [CmdletBinding(SupportsShouldProcess)]
        Param()
        function Local:Get-GroupByInputOrName(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [ValidateScript({ $_ -is [String] -or $_ -is [ADSI] })]
		    [Object]$InputObject
		) {
		    begin { Enter-Scope -Invocation $MyInvocation; }
		    end { Exit-Scope -Invocation $MyInvocation $Local:Group; }
		    process {
		        if ($Input -is [String]) {
		            [ADSI]$Local:Group = Get-Group -Name $InputObject;
		        } elseif ($Input.SchemaClassName -ne 'Group') {
		            throw "The supplied object is not a group.";
		        } else {
		            [ADSI]$Local:Group = $InputObject;
		        }
		    }
		}
		function Local:Get-UserByInputOrName(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [ValidateScript({ $_ -is [String] -or $_ -is [ADSI] })]
		    [Object]$InputObject
		) {
		    begin { Enter-Scope -Invocation $MyInvocation; }
		    end { Exit-Scope -Invocation $MyInvocation $Local:User; }
		    process {
		        if ($Input -is [String]) {
		            [ADSI]$Local:User = Get-User -Name $InputObject;
		        } elseif ($Input.SchemaClassName -ne 'User') {
		            throw "The supplied object is not a user.";
		        } else {
		            [ADSI]$Local:User = $InputObject;
		        }
		    }
		}
		function Get-FormattedUsers(
		    [Parameter(Mandatory)]
		    [ValidateNotNullOrEmpty()]
		    [ADSI[]]$Users
		) {
		    return $Users | ForEach-Object {
		        $Local:Path = $_.Path.Substring(8); # Remove the WinNT:// prefix
		        $Local:PathParts = $Local:Path.Split('/');
		        # The username is always last followed by the domain.
		        [PSCustomObject]@{
		            Name = $Local:PathParts[$Local:PathParts.Count - 1]
		            Domain = $Local:PathParts[$Local:PathParts.Count - 2]
		        };
		    };
		}
		function Test-MemberOfGroup(
		    [Parameter(Mandatory)]
		    [Object]$Group,
		    [Parameter(Mandatory)]
		    [Object]$Username
		) {
		    begin { Enter-Scope -Invocation $MyInvocation; }
		    end { Exit-Scope -Invocation $MyInvocation $Local:User; }
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
		    begin { Enter-Scope -Invocation $MyInvocation; }
		    end { Exit-Scope -Invocation $MyInvocation $Local:Group; }
		    process {
		        [ADSI]$Local:Group = [ADSI]"WinNT://$env:COMPUTERNAME/$Name,group";
		        return $Local:Group
		    }
		}
		function Get-GroupMembers(
		    [Parameter(Mandatory)]
		    [Object]$Group
		) {
		    begin { Enter-Scope -Invocation $MyInvocation; }
		    end { Exit-Scope -Invocation $MyInvocation $Local:Members; }
		    process {
		        [ADSI]$Local:Group = Get-GroupByInputOrName -InputObject $Group;
		        $Group.Invoke("Members") `
		            | ForEach-Object { [ADSI]$_ } `
		            | Where-Object {
		                $Local:Parent = $_.Parent.Substring(8); # Remove the WinNT:// prefix
		                $Local:Parent -ne 'NT AUTHORITY'
		            };
		    }
		}
		function Add-MemberToGroup(
		    [Parameter(Mandatory)]
		    [Object]$Group,
		    [Parameter(Mandatory)]
		    [Object]$Username
		) {
		    begin { Enter-Scope -Invocation $MyInvocation; }
		    end { Exit-Scope -Invocation $MyInvocation; }
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
		    [Object]$Group,
		    [Parameter(Mandatory)]
		    [Object]$Username
		) {
		    begin { Enter-Scope -Invocation $MyInvocation; }
		    end { Exit-Scope -Invocation $MyInvocation; }
		    process {
		        [ADSI]$Local:Group = Get-GroupByInputOrName -InputObject $Group;
		        [ADSI]$Local:User = Get-UserByInputOrName -InputObject $Username;
		        if (-not (Test-MemberOfGroup -Group $Local:Group -Username $Local:User)) {
		            Invoke-Verbose "User $Username is not a member of group $Group.";
		            return $False;
		        }
		        Invoke-Verbose "Removing user $Name from group $Group...";
		        $Local:Group.Invoke("Remove", $Local:User.Path);
		        return $True;
		    }
		}
		Export-ModuleMember -Function Add-MemberToGroup, Get-FormattedUsers, Get-Group, Get-GroupMembers, Get-UserByInputOrName, Remove-MemberFromGroup, Test-MemberOfGroup;
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
$Script:FAILED_TO_LOG = 1001;
$Script:FAILED_TO_CONNECT = 1002;
$Script:ALREADY_RUNNING = 1003;
$Script:FAILED_EXPECTED_VALUE = 1004;
$Script:FAILED_SETUP_ENVIRONMENT = 1005;
$Script:AGENT_FAILED_DOWNLOAD = 1011;
$Script:AGENT_FAILED_EXPAND = 1012;
$Script:AGENT_FAILED_FIND = 1013;
$Script:AGENT_FAILED_INSTALL = 1014;
$Script:FAILED_REGISTRY = 1021;
function Get-SoapResponse(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Uri
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:ParsedResponse; }
    process {
        [String]$Local:ContentType = "text/xml;charset=`"utf-8`"";
        [String]$Local:Method = "GET"
        $Local:Response = Invoke-RestMethod -Uri $Uri -ContentType $Local:ContentType -Method $Local:Method
        [System.Xml.XmlElement]$Local:ParsedResponse = $Local:Response.result
        $Local:ParsedResponse
    }
}
function Get-BaseUrl(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Service
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }
    process {
        "https://${Endpoint}/api/?apikey=$ApiKey&service=$Service"
    }
}
function Get-FormattedName2Id(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [Object[]]$InputArr,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ScriptBlock]$IdExpr
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    process {
        $InputArr | Select-Object -Property @{Name = 'Name'; Expression = { $_.name.'#cdata-section' } }, @{Name = 'Id'; Expression = $IdExpr }
    }
    end { Exit-Scope -Invocation $MyInvocation; }
}
function Invoke-EnsureLocalScript {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }
    process {
        [String]$Local:ScriptPath = $MyInvocation.PSScriptRoot;
        [String]$Local:TempPath = (Get-Item $env:TEMP).FullName;
        $Local:ScriptPath | Assert-NotNull -Message "Script path was null, this really shouldn't happen.";
        $Local:TempPath | Assert-NotNull -Message "Temp path was null, this really shouldn't happen.";
        if ($Local:ScriptPath -ne $Local:TempPath) {
            Invoke-Info "Copying script to temp folder...";
            [String]$Local:Into = "$Local:TempPath\$($MyInvocation.PSCommandPath | Split-Path -Leaf)";
            try {
                Copy-Item -Path $MyInvocation.PSCommandPath -Destination $Local:Into -Force;
            } catch {
                Invoke-Error "Failed to copy script to temp folder";
                Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:FAILED_SETUP_ENVIRONMENT;
            }
            Add-QueuedTask -QueuePhase $Phase -ScriptPath $Local:Into;
            Invoke-Info 'Exiting original process due to script being copied to temp folder...';
            Invoke-QuickExit;
        }
    }
}
function Invoke-EnsureSetupInfo {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }
    process {
        [String]$Local:File = "$($env:TEMP)\InstallInfo.json";
        If (Test-Path $Local:File) {
            Invoke-Info "Install Info exists, checking validity...";
            try {
                [PSCustomObject]$Local:InstallInfo = Get-Content -Path $Local:File -Raw | ConvertFrom-Json;
                $Local:InstallInfo | Assert-NotNull -Message "Install info was null";
                [String]$Local:DeviceName = $Local:InstallInfo.DeviceName;
                $Local:DeviceName | Assert-NotNull -Message "Device name was null";
                [String]$Local:ClientId = $Local:InstallInfo.ClientId;
                $Local:ClientId | Assert-NotNull -Message "Client id was null";
                [String]$Local:SiteId = $Local:InstallInfo.SiteId;
                $Local:SiteId | Assert-NotNull -Message "Site id was null";
                [String]$Local:Path = $Local:InstallInfo.Path;
                $Local:Path | Assert-NotNull -Message "Path was null";
                return $Local:InstallInfo;
            } catch {
                Invoke-Warn 'There was an issue with the install info, deleting the file for recreation...';
                Remove-Item -Path $Local:File -Force;
            }
        }
        Invoke-Info 'No install info found, creating new install info...';
        #region - Get Client Selection
        $Local:Clients = (Get-SoapResponse -Uri (Get-BaseUrl "list_clients")).items.client;
        $Local:Clients | Assert-NotNull -Message "Failed to get clients from N-Able";
        $Local:FormattedClients = Get-FormattedName2Id -InputArr $Clients -IdExpr { $_.clientid }
        $Local:FormattedClients | Assert-NotNull -Message "Failed to format clients";
        $Local:SelectedClient = Get-PopupSelection -Items $Local:FormattedClients -Title "Please select a Client";
        #endregion - Get Client Selection
        #region - Get Site Selection
        $Local:Sites = (Get-SoapResponse -Uri "$(Get-BaseUrl "list_sites")&clientid=$($SelectedClient.Id)").items.site;
        $Local:Sites | Assert-NotNull -Message "Failed to get sites from N-Able";
        $Local:FormattedSites = Get-FormattedName2Id -InputArr $Sites -IdExpr { $_.siteid };
        $Local:FormattedSites | Assert-NotNull -Message "Failed to format sites";
        $Local:SelectedSite = Get-PopupSelection -Items $Local:FormattedSites -Title "Please select a Site";
        #endregion - Get Site Selection
        # TODO - Show a list of devices for the selected client so the user can confirm they're using the correct naming convention
        [String]$Local:DeviceName = Get-UserInput -Title "Device Name" -Question "Enter a name for this device"
        [PSCustomObject]$Local:InstallInfo = @{
            "DeviceName" = $Local:DeviceName
            "ClientId"   = $Local:SelectedClient.Id
            "SiteId"     = $Local:SelectedSite.Id
            "Path"       = $Local:File
        };
        Invoke-Info "Saving install info to $Local:File...";
        try {
            $Local:InstallInfo | ConvertTo-Json | Out-File -FilePath $File -Force;
        } catch {
            Invoke-Error "There was an issue saving the install info to $Local:File";
            Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:FAILED_SETUP_ENVIRONMENT;
        }
        return $Local:InstallInfo;
    }
}
function Remove-QueuedTask {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }
    process {
        [CimInstance]$Local:Task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue;
        if (-not $Local:Task) {
            Invoke-Verbose -Message "Scheduled task [$TaskName] does not exist, skipping removal...";
            return;
        }
        Invoke-Verbose -Message "Removing scheduled task [$TaskName]...";
        $Local:Task | Unregister-ScheduledTask -ErrorAction Stop -Confirm:$false;
    }
}
function Add-QueuedTask(
    [Parameter(Mandatory)]
    [ValidateSet("Configure", "Cleanup", "Install", "Update", "Finish")]
    [String]$QueuePhase,
    [Parameter(HelpMessage="The path of the script to run when the task is triggered.")]
    [ValidateNotNullOrEmpty()]
    [String]$ScriptPath = $MyInvocation.PSCommandPath,
    [switch]$OnlyOnRebootRequired = $false,
    [switch]$ForceReboot = $false
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }
    process {
        [Boolean]$Local:RequiresReboot = (Get-RebootFlag).Required();
        if ($OnlyOnRebootRequired -and (-not ($Local:RequiresReboot -or $ForceReboot))) {
            Invoke-Info "The device does not require a reboot before the $QueuePhase phase can be started, skipping queueing...";
            return;
        }
        # Schedule the task before possibly rebooting.
        $Local:Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -WakeToRun;
        [String]$Local:RunningUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name;
        $Local:RunningUser | Assert-NotNull -Message "Running user was null, this really shouldn't happen.";
        $Local:Principal = New-ScheduledTaskPrincipal -UserId $Local:RunningUser -RunLevel Highest;
        $Local:Trigger = switch ($Local:RequiresReboot) {
            $true { New-ScheduledTaskTrigger -AtLogOn -User $Local:RunningUser; }
            $false { New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5); }
        };
        [Int]$Local:RecursionLevel = if ($Phase -eq $QueuePhase) { $RecursionLevel + 1 } else { 0 };
        [String[]]$Local:AdditionalArgs = @("-Phase $QueuePhase", "-RecursionLevel $Local:RecursionLevel");
        if ($WhatIfPreference) {
            $Local:AdditionalArgs += "-WhatIf";
        }
        if ($VerbosePreference -ne "SilentlyContinue") {
            $Local:AdditionalArgs += "-Verbose";
        }
        $Local:Action = New-ScheduledTaskAction `
            -Execute 'powershell.exe' `
            -Argument "-ExecutionPolicy Bypass -NoExit -File `"$ScriptPath`" $($Local:AdditionalArgs -join ' ')";
        $Local:Task = New-ScheduledTask `
            -Action $Local:Action `
            -Principal $Local:Principal `
            -Settings $Local:Settings `
            -Trigger $Local:Trigger;
        Register-ScheduledTask -TaskName $TaskName -InputObject $Task -Force -ErrorAction Stop | Out-Null;
        if ($Local:RequiresReboot) {
            Invoke-Info "The device requires a reboot before the $QueuePhase phase can be started, rebooting in 15 seconds...";
            Invoke-Timeout
                -Timeout 15 `
                -AllowCancel `
                -Activity 'Reboot' `
                -StatusMessage 'Rebooting in {0} seconds...' `
                -TimeoutScript {
                    Invoke-Info 'Rebooting now...';
                    (Get-RunningFlag).Remove();
                    (Get-RebootFlag).Remove();
                    Restart-Computer -Force;
                } `
                -CancelScript {
                    Invoke-Info 'Reboot cancelled, please reboot to continue.';
                };
        }
    }
}
function Invoke-PhaseConfigure([Parameter(Mandatory)][ValidateNotNullOrEmpty()][PSCustomObject]$InstallInfo) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:NextPhase; }
    process {
        $InstallInfo | Assert-NotNull -Message "Install info was null";
        #region - Device Name
        [String]$Local:DeviceName = $InstallInfo.DeviceName;
        $Local:DeviceName | Assert-NotNull -Message "Device name was null";
        [String]$Local:ExistingName = $env:COMPUTERNAME;
        $Local:ExistingName | Assert-NotNull -Message "Existing name was null"; # TODO :: Alternative method of getting existing name if $env:COMPUTERNAME is null
        if ($Local:ExistingName -eq $Local:DeviceName) {
            Invoke-Info "Device name is already set to $Local:DeviceName.";
        } else {
            Invoke-Info "Device name is not set to $Local:DeviceName, setting it now...";
            Rename-Computer -NewName $Local:DeviceName;
            (Get-RebootFlag).Set($null);
        }
        #endregion - Device Name
        #region - Auto-Login
        [String]$Local:RegKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon";
        try {
            $ErrorActionPreference = "Stop";
            Set-ItemProperty -Path $Local:RegKey -Name "AutoAdminLogon" -Value 1 | Out-Null;
            Set-ItemProperty -Path $Local:RegKey -Name "DefaultUserName" -Value "localadmin" | Out-Null;
            Set-ItemProperty -Path $Local:RegKey -Name "DefaultPassword" -Value "" | Out-Null;
            Invoke-Info 'Auto-login registry keys set.';
        } catch {
            Invoke-Error "Failed to set auto-login registry keys";
            Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:FAILED_REGISTRY;
        }
        #endregion - Auto-Login
        [String]$Local:NextPhase = "Cleanup";
        return $Local:NextPhase;
    }
}
function Invoke-PhaseCleanup {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:NextPhase; }
    process {
        function Invoke-Progress {
            Param(
                [Parameter(Mandatory)][ValidateNotNull()]
                [ScriptBlock]$GetItems,
                [Parameter(Mandatory)][ValidateNotNull()]
                [ScriptBlock]$ProcessItem,
                [ValidateNotNull()]
                [ScriptBlock]$GetItemName = { Param($Item) $Item; },
                [ScriptBlock]$FailedProcessItem
            )
            [String]$Local:ProgressActivity = $MyInvocation.MyCommand.Name;
            Write-Progress -Activity $Local:ProgressActivity -CurrentOperation "Getting items..." -PercentComplete 0;
            Write-Debug 'Getting items';
            [Object[]]$Local:InputItems = $GetItems.InvokeReturnAsIs();
            Write-Progress -Activity $Local:ProgressActivity -PercentComplete 10;
            if ($null -eq $Local:InputItems -or $Local:InputItems.Count -eq 0) {
                Write-Progress -Activity $Local:ProgressActivity -Status "No items found." -PercentComplete 100 -Completed;
                Invoke-Debug 'No Items found';
                return;
            } else {
                Write-Progress -Activity $Local:ProgressActivity -Status "Processing $($Local:InputItems.Count) items...";
                Invoke-Debug "Processing $($Local:InputItems.Count) items...";
            }
            [System.Collections.IList]$Local:FailedItems = New-Object System.Collections.Generic.List[System.Object];
            [Int]$Local:PercentPerItem = 90 / $Local:InputItems.Count;
            [Int]$Local:PercentComplete = 0;
            foreach ($Local:Item in $Local:InputItems) {
                [String]$Local:ItemName = $GetItemName.InvokeReturnAsIs($Local:Item);
                Write-Debug "Processing item [$Local:ItemName]...";
                Write-Progress -Activity $Local:ProgressActivity -CurrentOperation "Processing item [$Local:ItemName]..." -PercentComplete $Local:PercentComplete;
                try {
                    $ErrorActionPreference = "Stop";
                    $ProcessItem.InvokeReturnAsIs($Local:Item);
                } catch {
                    Invoke-Warn "Failed to process item [$Local:ItemName]";
                    Invoke-Debug -Message "Due to reason - $($_.Exception.Message)";
                    try {
                        $ErrorActionPreference = "Stop";
                        if ($null -eq $FailedProcessItem) {
                            $Local:FailedItems.Add($Local:Item);
                        } else { $FailedProcessItem.InvokeReturnAsIs($Local:Item); }
                    } catch {
                        Invoke-Warn "Failed to process item [$Local:ItemName] in failed process item block";
                    }
                }
                $Local:PercentComplete += $Local:PercentPerItem;
            }
            Write-Progress -Activity $Local:ProgressActivity -PercentComplete 100 -Completed;
            if ($Local:FailedItems.Count -gt 0) {
                Invoke-Warn "Failed to process $($Local:FailedItems.Count) items";
                Invoke-Warn "Failed items: `n`t$($Local:FailedItems -join "`n`t")";
            }
        }
        function Stop-Services_HP {
            begin { Enter-Scope -Invocation $MyInvocation; }
            end { Exit-Scope -Invocation $MyInvocation; }
            process {
                [String[]]$Services = @("HotKeyServiceUWP", "HPAppHelperCap", "HP Comm Recover", "HPDiagsCap", "HotKeyServiceUWP", "LanWlanWwanSwitchingServiceUWP", "HPNetworkCap", "HPSysInfoCap", "HP TechPulse Core");
                Invoke-Info "Disabling $($Services.Count) services...";
                Invoke-Progress -GetItems { $Services; } -ProcessItem {
                    Param([String]$ServiceName)
                    try {
                        $ErrorActionPreference = 'Stop';
                        $Local:Instance = Get-Service -Name $ServiceName;
                    } catch {
                        Invoke-Warn "Skipped service $ServiceName as it isn't installed.";
                    }
                    if ($Local:Instance) {
                        Invoke-Info "Stopping service $Local:Instance...";
                        try {
                            $ErrorActionPreference = 'Stop';
                            $Local:Instance | Stop-Service -Force -Confirm:$false;
                            Invoke-Info "Stopped service $Local:Instance";
                        } catch {
                            Invoke-Info -Message "Failed to stop $Local:Instance";
                        }
                        Invoke-Info "Disabling service $ServiceName...";
                        try {
                            $ErrorActionPreference = 'Stop';
                            $Local:Instance | Set-Service -StartupType Disabled -Confirm:$false;
                            Invoke-Info "Disabled service $ServiceName";
                        } catch {
                            Invoke-Warn "Failed to disable $ServiceName";
                            Invoke-Debug -Message "Due to reason - $($_.Exception.Message)";
                        }
                    }
                };
            }
        }
        function Remove-Programs_HP {
            begin { Enter-Scope -Invocation $MyInvocation; }
            end { Exit-Scope -Invocation $MyInvocation; }
            process {
                [String[]]$Programs = @(
                    'HPJumpStarts'
                    'HPPCHardwareDiagnosticsWindows'
                    'HPPowerManager'
                    'HPPrivacySettings'
                    'HPSupportAssistant'
                    'HPSureShieldAI'
                    'HPSystemInformation'
                    'HPQuickDrop'
                    'HPWorkWell'
                    'myHP'
                    'HPDesktopSupportUtilities'
                    'HPQuickTouch'
                    'HPEasyClean'
                    'HPPCHardwareDiagnosticsWindows'
                    'HPProgrammableKey'
                );
                [String[]]$UninstallablePrograms = @(
                    "HP Device Access Manager"
                    "HP Client Security Manager"
                    "HP Connection Optimizer"
                    "HP Documentation"
                    "HP MAC Address Manager"
                    "HP Notifications"
                    "HP System Info HSA Service"
                    "HP Security Update Service"
                    "HP System Default Settings"
                    "HP Sure Click"
                    "HP Sure Click Security Browser"
                    "HP Sure Run"
                    "HP Sure Run Module"
                    "HP Sure Recover"
                    "HP Sure Sense"
                    "HP Sure Sense Installer"
                    "HP Wolf Security"
                    "HP Wolf Security - Console"
                    "HP Wolf Security Application Support for Sure Sense"
                    "HP Wolf Security Application Support for Windows"
                );
                Invoke-Progress `
                    -GetItems { Get-Package | Where-Object { $UninstallablePrograms -contains $_.Name -or $Programs -contains $_.Name } } `
                    -GetItemName { Param([Microsoft.PackageManagement.Packaging.SoftwareIdentity]$Program) $Program.Name; } `
                    -ProcessItem {
                        Param([Microsoft.PackageManagement.Packaging.SoftwareIdentity]$Program)
                        $Local:Product = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq $Program.Name };
                        if (-not $Local:Product) {
                            throw "Can't find MSI Package for program [$($Program.Name)]";
                        } else {
                            msiexec /x $Local:Product.IdentifyingNumber /quiet /noreboot | Out-Null;
                            Invoke-Info "Sucessfully removed program [$($Local:Product.Name)]";
                        }
                    };
            }
        }
        function Remove-ProvisionedPackages_HP {
            begin { Enter-Scope -Invocation $MyInvocation; }
            end { Exit-Scope -Invocation $MyInvocation; }
            process {
                [String]$HPIdentifier = "AD2F1837";
                Invoke-Progress -GetItems { Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -match "^$HPIdentifier" } } -ProcessItem {
                    Param($Package)
                    Remove-AppxProvisionedPackage -PackageName $Package.PackageName -Online -AllUsers | Out-Null;
                    Invoke-Info "Sucessfully removed provisioned package [$($Package.DisplayName)]";
                }
            }
        }
        function Remove-AppxPackages_HP {
            begin { Enter-Scope -Invocation $MyInvocation; }
            end { Exit-Scope -Invocation $MyInvocation; }
            process {
                [String]$HPIdentifier = "AD2F1837";
                Invoke-Progress -GetItems { Get-AppxPackage -AllUsers | Where-Object { $_.Name -match "^$HPIdentifier" } } -ProcessItem {
                    Param($Package)
                    Remove-AppxPackage -Package $Package.PackageFullName -AllUsers;
                    Invoke-Info "Sucessfully removed appx-package [$($Package.Name)]";
                };
            }
        }
        function Remove-Drivers_HP {
            begin { Enter-Scope -Invocation $MyInvocation; }
            end { Exit-Scope -Invocation $MyInvocation; }
            process {
                # Uninstalling the drivers disables and (on reboot) removes the installed services.
                # At this stage the only 'HP Inc.' driver we want to keep is HPSFU, used for firmware servicing.
                Invoke-Progress `
                    -GetItems { Get-WindowsDriver -Online | Where-Object { $_.ProviderName -eq 'HP Inc.' -and $_.OriginalFileName -notlike '*\hpsfuservice.inf' }; } `
                    -GetItemName { Param([Microsoft.Dism.Commands.BasicDriverObject]$Driver) $Driver.OriginalFileName.ToString(); } `
                    -ProcessItem {
                        Param([Microsoft.Dism.Commands.BasicDriverObject]$Driver)
                        [String]$Local:FileName = $Driver.OriginalFileName.ToString();
                        try {
                            $ErrorActionPreference = 'Stop';
                            pnputil /delete-driver $Local:FileName /uninstall /force;
                            Invoke-Info "Removed driver: $($Local:FileName)";
                        } catch {
                            Invoke-Warn "Failed to remove driver: $($Local:FileName): $($_.Exception.Message)";
                        }
                    };
                # Once the drivers are gone lets disable installation of 'drivers' for these HP 'devices' (typically automatic via Windows Update)
                # SWC\HPA000C = HP Device Health Service
                # SWC\HPIC000C = HP Application Enabling Services
                # SWC\HPTPSH000C = HP Services Scan
                # ACPI\HPIC000C = HP Application Driver
                @{
                    'HKLM:\Software\Policies\Microsoft\Windows\DeviceInstall\Restrictions\DenyDeviceIDs' = @{
                        KIND = 'String';
                        Values = @{
                            1 = 'SWC\HPA000C'
                            2 = 'SWC\HPIC000C'
                            3 = 'SWC\HPTPSH000C'
                            4 = 'ACPI\HPIC000C'
                        };
                    };
                    'HKLM:\Software\Policies\Microsoft\Windows\DeviceInstall\Restrictions' = @{
                        KIND = 'DWORD';
                        Values = @{
                            DenyDeviceIDs = 1;
                            DenyDeviceIDsRetroactive = 1;
                        };
                    };
                }.GetEnumerator() | ForEach-Object {
                    [String]$Local:RegistryPath = $_.Key;
                    [HashTable]$Local:RegistryTable = $_.Value;
                    If (-not (Test-Path $Local:RegistryPath)) {
                        New-Item -Path $Local:RegistryPath -Force | Out-Null
                    } else {
                        Invoke-Info "Registry path [$Local:RegistryPath] already exists, skipping creation...";
                    }
                    $Local:RegistryTable.Values.GetEnumerator() | ForEach-Object {
                        [String]$Local:ValueName = $_.Key;
                        [String]$Local:ValueData = $_.Value;
                        If (-not (Test-Path "$Local:RegistryPath\$Local:ValueName")) {
                            New-ItemProperty -Path $Local:RegistryPath -Name $Local:ValueName -Value $Local:ValueData -PropertyType $Local:RegistryTable.KIND | Out-Null;
                            Invoke-Info "Created registry value [$Local:ValueName] with data [$Local:ValueData] in path [$Local:RegistryPath]";
                        } else {
                            Invoke-Info "Registry value [$Local:ValueName] already exists in path [$Local:RegistryPath], skipping creation...";
                        }
                    }
                }
            }
        }
        Stop-Services_HP;
        Remove-ProvisionedPackages_HP;
        Remove-AppxPackages_HP;
        Remove-Programs_HP;
        [String]$Local:NextPhase = "Install";
        return $Local:NextPhase;
    }
}
function Invoke-PhaseInstall([Parameter(Mandatory)][ValidateNotNullOrEmpty()][PSCustomObject]$InstallInfo) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:NextPhase; }
    process {
        [String]$Local:AgentServiceName = "Advanced Monitoring Agent";
        [String]$Local:NextPhase = "Update";
        # Check if the agent is already installed and running.
        if (Get-Service -Name $Local:AgentServiceName -ErrorAction SilentlyContinue) {
            Invoke-Info "Agent is already installed, skipping installation...";
            return $Local:NextPhase;
        }
        Invoke-WithinEphemeral {
            [String]$Local:ClientId = $InstallInfo.ClientId;
            [String]$Local:SiteId = $InstallInfo.SiteId;
            [String]$Local:Uri = "https://system-monitor.com/api/?apikey=${ApiKey}&service=get_site_installation_package&endcustomerid=${ClientId}&siteid=${SiteId}&os=windows&type=remote_worker";
            Invoke-Info "Downloading agent from [$Local:Uri]";
            try {
                $ErrorActionPreference = "Stop";
                Invoke-WebRequest -Uri $Local:Uri -OutFile 'agent.zip' -UseBasicParsing;
            } catch {
                Invoke-Error "Failed to download agent from [$Local:Uri]";
                Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:AGENT_FAILED_DOWNLOAD;
            }
            Invoke-Info "Expanding archive...";
            try {
                $ErrorActionPreference = "Stop";
                Expand-Archive -Path 'agent.zip' -DestinationPath $PWD | Out-Null;
            } catch {
                Invoke-Error "Failed to expand archive";
                Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:AGENT_FAILED_EXPAND;
            }
            Invoke-Info "Finding agent executable...";
            try {
                $ErrorActionPreference = 'Stop';
                [String]$Local:OutputExe = Get-ChildItem -Path $PWD -Filter '*.exe' -File;
                $Local:OutputExe | Assert-NotNull -Message "Failed to find agent executable";
            } catch {
                Invoke-Info "Failed to find agent executable";
                Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:AGENT_FAILED_FIND;
            }
            Invoke-Info "Installing agent from [$Local:OutputExe]...";
            try {
                $ErrorActionPreference = 'Stop';
                [System.Diagnostics.Process]$Local:Installer = Start-Process -FilePath $Local:OutputExe -Wait -PassThru;
                $Local:Installer.ExitCode | Assert-Equals -Expected 0 -Message "Agent installer failed with exit code [$($Local:Installer.ExitCode)]";
                (Get-RebootFlag).Set($null);
            } catch {
                Invoke-Error "Failed to install agent from [$Local:OutputExe]";
                Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:AGENT_FAILED_INSTALL;
            }
        }
        Invoke-Info 'Unable to determine when the agent is fully installed, sleeping for 5 minutes...';
        Invoke-Timeout -Timeout 300 -Activity 'Agent Installation' -StatusMessage 'Waiting for agent to be installed...';
        # TODO - Query if sentinel is configured, if so wait for sentinel and the agent to be running services, then restart the computer
        return $Local:NextPhase;
    }
}
function Invoke-PhaseUpdate {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:NextPhase; }
    process {
        [String]$Local:NextPhase = if ($RecursionLevel -ge 2) { "Finish" } else { "Update" };
        Get-WindowsUpdate -Install -AcceptAll -AutoReboot:$false -IgnoreReboot -IgnoreUserInput -Confirm:$false;
        (Get-RebootFlag).Set($null);
        return $Local:NextPhase;
    }
}
function Invoke-PhaseFinish {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:NextPhase; }
    process {
        [String]$Local:NextPhase = $null;
        #region - Remove localadmin Auto-Login
        $Local:RegKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon";
        try {
            $ErrorActionPreference = "Stop";
            Remove-ItemProperty -Path $Local:RegKey -Name "AutoAdminLogon" -Force -ErrorAction Stop;
            Remove-ItemProperty -Path $Local:RegKey -Name "DefaultUserName" -Force -ErrorAction Stop;
            Remove-ItemProperty -Path $Local:RegKey -Name "DefaultPassword" -Force -ErrorAction Stop;
        } catch {
            Invoke-Error "Failed to remove auto-login registry keys";
            Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:FAILED_REGISTRY;
        }
        #endregion - Remove localadmin Auto-Login
        return $Local:NextPhase;
    }
}

(New-Module -ScriptBlock $Global:EmbededModules['Environment.psm1'] -AsCustomObject -ArgumentList $MyInvocation.BoundParameters).'Invoke-RunMain'($MyInvocation, {
    Register-ExitHandler -Name 'Running Flag Removal' -ExitHandler {
        (Get-RunningFlag).Remove();
    };
    Register-ExitHandler -Name 'Queued Task Removal' -OnlyFailure -ExitHandler {
        Remove-QueuedTask;
    };
    # Ensure only one process is running at a time.
    If ((Get-RunningFlag).IsRunning()) {
        Invoke-Error "The script is already running in another session, exiting...";
        Exit $Script:ALREADY_RUNNING;
    } else {
        (Get-RunningFlag).Set($null);
        Remove-QueuedTask;
    }
    Invoke-EnsureLocalScript;
    # There is an issue with the CimInstance LastBootUpTime where it returns the incorrect time on first boot.
    # To work around this if there was previously no connecting and we have just connected we can assume its a new setup, and force a reboot to ensure the correct time is returned.
    # TODO - Find a better way to determine if this is a first boot.
    $Local:PossibleFirstBoot = Invoke-EnsureNetwork -Name $NetworkName -Password ($NetworkPassword | ConvertTo-SecureString -AsPlainText -Force);
    Invoke-EnsureModules -Modules @('PSWindowsUpdate');
    $Local:InstallInfo = Invoke-EnsureSetupInfo;
    # Queue this phase to run again if a restart is required by one of the environment setups.
    Add-QueuedTask -QueuePhase $Phase -OnlyOnRebootRequired -ForceReboot:$Local:PossibleFirstBoot;
    [String]$Local:NextPhase = $null;
    switch ($Phase) {
        'configure' { [String]$Local:NextPhase = Invoke-PhaseConfigure -InstallInfo $Local:InstallInfo; }
        'cleanup' { [String]$Local:NextPhase = Invoke-PhaseCleanup; }
        'install' { [String]$Local:NextPhase = Invoke-PhaseInstall -InstallInfo $Local:InstallInfo; }
        'update' { [String]$Local:NextPhase = Invoke-PhaseUpdate; }
        'finish' { [String]$Local:NextPhase = Invoke-PhaseFinish; }
    }
    # Should only happen when we are done and there is nothing else to queue.
    if (-not $Local:NextPhase) {
        Invoke-Info "No next phase was returned, exiting...";
        return
    }
    Invoke-Info "Queueing next phase [$Local:NextPhase]...";
    Add-QueuedTask -QueuePhase $Local:NextPhase;
});
