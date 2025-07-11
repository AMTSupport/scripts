#Requires -Version 5.1
#Requires -RunAsAdministrator

Using module ..\..\common\Environment.psm1
Using module ..\..\common\Logging.psm1
Using module ..\..\common\Scope.psm1
Using module ..\..\common\Exit.psm1
Using module ..\..\common\Flag.psm1
Using module ..\..\common\Input.psm1
Using module ..\..\common\Assert.psm1
Using module ..\..\common\Ensure.psm1
Using module ..\..\common\Windows.psm1
Using module ..\..\common\Temp.psm1

Using module PSWindowsUpdate
Using module PowerShellGet
Using module PackageManagement

# Windows 10 Setup screen raw inputs
# enter                                             - Language
# down,enter,enter                                  - Keyboard
# tab,tab,tab,enter                                 - Skip Network Setup
# tab,tab,tab,tab,tab,tab,enter                     - Skip Second Network Setup
# tab,tab,tab,tab,enter                             - Terms and Conditions
# localadmin,enter,enter                            - Create Local Account
# enter                                             - Permissions
# shift+tab,enter                                   - Disable Cortana
# tab,tab,tab,tab,tab,enter,tab,tab,tab,tab,enter   - Skip HP Bullshit

# After Windows Setup
# windows,powershell,right,down,enter,left,enter                            - Open PowerShell as Admin
# Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process,enter,a,enter  - Set Execution Policy
# D:\Other\AutoSetup.ps1,enter                                              - Run the setup Script

[CmdletBinding(SupportsShouldProcess)]
Param (
    [Parameter()]
    [ValidateSet('SetupWindows', 'Configure', 'Cleanup', 'Install', 'Update', 'Finish')]
    [String]$Phase = 'Configure',

    [Parameter(DontShow)]
    [ValidateLength(32, 32)]
    [String]$ApiKey,

    [Parameter(DontShow)]
    [ValidateNotNullOrEmpty()]
    [String]$Endpoint = 'system-monitor.com',

    [Parameter(DontShow)]
    [ValidateNotNullOrEmpty()]
    [String]$NetworkName = 'Guests',

    [Parameter(DontShow)]
    [ValidateNotNullOrEmpty()]
    [SecureString]$NetworkPassword,

    [Parameter(DontShow)]
    [ValidateNotNullOrEmpty()]
    [String]$TaskName = 'SetupScheduledTask',

    [Parameter(DontShow)]
    [ValidateNotNullOrEmpty()]
    [Int]$RecursionLevel = 0
)

#region - Error Codes

$Script:ALREADY_RUNNING = 1003;
$Script:FAILED_SETUP_ENVIRONMENT = 1005;

$Script:AGENT_FAILED_DOWNLOAD = 1011;
$Script:AGENT_FAILED_EXPAND = 1012;
$Script:AGENT_FAILED_FIND = 1013;
$Script:AGENT_FAILED_INSTALL = 1014;

$Script:FAILED_REGISTRY = 1021;

#endregion - Error Codes

#region - Utility Functions

function Get-SoapResponse(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Uri
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:ParsedResponse; }

    process {
        [String]$Local:ContentType = "text/xml;charset=`"utf-8`"";
        [String]$Local:Method = 'GET'

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
    begin { Enter-Scope; }
    end { Exit-Scope; }

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
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        $InputArr | Select-Object -Property @{Name = 'Name'; Expression = { $_.name.'#cdata-section' } }, @{Name = 'Id'; Expression = $IdExpr }
    }
}

function Test-ConfigValueOrSave {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Key,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]$GetBlock,

        [Parameter(Mandatory)]
        [PSCustomObject]$InstallInfo
    )

    Invoke-Info "Testing for $Key in install info...";
    Invoke-Info "Install Info: $($InstallInfo | ConvertTo-Json)";

    if (-not ($InstallInfo.PSObject.Properties.Name -contains $Key)) {
        $Value = $GetBlock.InvokeWithContext($null, [PSVariable]::new('_', $InstallInfo));
        Invoke-Info "Adding $Key to install info with value $Value...";
        $InstallInfo | Add-Member -MemberType NoteProperty -Name:$Key -Value:$Value;

        Invoke-Info "Saving install info to $($InstallInfo.Path)...";
        try {
            $InstallInfo | ConvertTo-Json | Set-Content -Path:$($InstallInfo.Path) -Force;
        } catch {
            Invoke-Error "There was an issue saving the install info to $Local:File";
            Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:FAILED_SETUP_ENVIRONMENT;
        }
    }
}

function Update-ToWin11(
    [bool]$Queue = $True
) {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [String]$Private:OSCaption = (Get-CimInstance -Query 'select caption from win32_operatingsystem' | Select-Object -Property Caption).Caption;
        if ($Private:OSCaption -match 'Windows 11') {
            return;
        }

        Invoke-Debug 'Windows 10 detected, continuing...';

        # $Private:Manufacturer = (Get-WmiObject -Class Win32_ComputerSystem).Manufacturer;
        $Private:InstallInfo = Get-InstallInfo -GetOnly;
        Test-ConfigValueOrSave -InstallInfo:$Private:InstallInfo -Key 'UpgradeToWin11' -GetBlock {
            Get-UserConfirmation 'Upgrade windows' 'Do you want to upgrade to Windows 11?' $True;
        };

        if (-not $Private:InstallInfo.UpgradeToWin11) {
            Invoke-Info 'User chose not to upgrade to Windows 11.';
            return;
        }

        $Private:OutputFile = "$env:TEMP\Windows11InstallationAssistant.exe";
        Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?linkid=2171764' -OutFile $Private:OutputFile -UseBasicParsing;
        Unblock-File -Path $Private:OutputFile;

        Invoke-Info 'Starting Windows 11 upgrade, this will take a while with no progress bar...';
        try {
            # TODO - Maybe use the processes resource monitor to determine if its downloading, copying or what?
            Start-Process -FilePath $Private:OutputFile -ArgumentList '/QuietInstall /SkipEULA /auto upgrade /NoRestartUI /UninstallUponUpgrade' -Wait;

            if ($Queue) {
                Invoke-Info 'Windows 11 upgrade completed successfully, rebooting now...';
                Add-QueuedTask -QueuePhase $Phase -ForceReboot:$True;
            } else {
                Invoke-Info 'Windows 11 upgrade completed successfully, please reboot to continue...';
            }
        } catch {
            Invoke-Error 'Failed to start Windows 11 upgrade';
            Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:FAILED_SETUP_ENVIRONMENT;
        }
    }
}

#endregion - Utility Functions

#region - Environment Setup

# If the script isn't located in the temp folder, copy it there and run it from there.
# Also treat this as an indication that the computer hasn't rebooted yet and restart.
function Invoke-EnsureLocalScript {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [String]$Local:ScriptPath = $MyInvocation.PSScriptRoot;
        [String]$Local:TempPath = (Get-Item $env:TEMP).FullName;

        $Local:ScriptPath | Assert-NotNull -Message "Script path was null, this really shouldn't happen.";
        $Local:TempPath | Assert-NotNull -Message "Temp path was null, this really shouldn't happen.";

        if ($Local:ScriptPath -ne $Local:TempPath) {
            Invoke-Info 'Copying script to temp folder...';
            [String]$Local:Into = "$Local:TempPath\$($MyInvocation.PSCommandPath | Split-Path -Leaf)";

            try {
                Copy-Item -Path $MyInvocation.PSCommandPath -Destination $Local:Into -Force;
            } catch {
                Invoke-Error 'Failed to copy script to temp folder';
                Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:FAILED_SETUP_ENVIRONMENT;
            }

            if ($PSCmdlet.ShouldProcess('Running script from temp folder')) {
                (Get-RebootFlag).Set($null);

                Add-QueuedTask -QueuePhase $Phase -ScriptPath $Local:Into;
                Invoke-Info 'Exiting original process due to script being copied to temp folder...';
                Invoke-QuickExit;
            }
        }
    }
}

function Get-InstallInfo(
    [Parameter(HelpMessage = 'Don''t prompt user for any questions, instead only return what is already saved in the install info.')]
    [ValidateNotNullOrEmpty()]
    [Switch]$GetOnly
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:InstallInfo; }

    process {
        [String]$Local:File = "$($env:TEMP)\InstallInfo.json";

        If (Test-Path $Local:File) {
            try {
                [PSCustomObject]$Local:InstallInfo = Get-Content -Path $Local:File -Raw | ConvertFrom-Json;
            } catch {
                Invoke-Error "There was an issue reading the install info from $Local:File";
                Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:FAILED_SETUP_ENVIRONMENT;
            }
        }

        if (-not $Local:InstallInfo) {
            [PSCustomObject]$Local:InstallInfo = @{ Path = $Local:File; };
        }

        if ($GetOnly) {
            return $Local:InstallInfo;
        }

        Test-ConfigValueOrSave -InstallInfo:$Local:InstallInfo -Key 'ClientId' -GetBlock {
            $Local:Clients = (Get-SoapResponse -Uri (Get-BaseUrl 'list_clients')).items.client;
            $Local:Clients | Assert-NotNull -Message 'Failed to get clients from N-Able';

            $Local:FormattedClients = Get-FormattedName2Id -InputArr $Clients -IdExpr { $_.clientid }
            $Local:FormattedClients | Assert-NotNull -Message 'Failed to format clients';

            (Get-PopupSelection -Items $Local:FormattedClients -Title 'Please select a Client').Id;
        };

        Test-ConfigValueOrSave -InstallInfo:$Local:InstallInfo -Key 'SiteId' -GetBlock {
            $Local:Sites = (Get-SoapResponse -Uri "$(Get-BaseUrl 'list_sites')&clientid=$($_.ClientId)").items.site;
            $Local:Sites | Assert-NotNull -Message 'Failed to get sites from N-Able';

            $Local:FormattedSites = Get-FormattedName2Id -InputArr $Sites -IdExpr { $_.siteid };
            $Local:FormattedSites | Assert-NotNull -Message 'Failed to format sites';

            (Get-PopupSelection -Items $Local:FormattedSites -Title 'Please select a Site').Id;
        };

        Test-ConfigValueOrSave -InstallInfo:$Local:InstallInfo -Key 'DeviceName' -GetBlock {
            # TODO - Show a list of devices for the selected client so the user can confirm they're using the correct naming convention
            Get-UserInput -Title 'Device Name' -Question 'Enter a name for this device'
        };

        return $Local:InstallInfo;
    }
}

#endregion - Environment Setup

#region - Queue Functions

function Remove-QueuedTask {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        try {
            [CimInstance]$Local:Task = Get-ScheduledTask -TaskName $TaskName;

            if ($PSCmdlet.ShouldProcess("Removing scheduled task [$TaskName]")) {
                $Local:Task | Unregister-ScheduledTask -ErrorAction Stop -Confirm:$false;
                Invoke-Verbose -Message "Removed scheduled task [$TaskName]...";
            }
        } catch {
            Invoke-Verbose -Message "Scheduled task [$TaskName] does not exist, skipping removal...";
            return;
        }
    }
}

function Add-QueuedTask(
    [Parameter(Mandatory)]
    [ValidateSet('Configure', 'Cleanup', 'Install', 'Update', 'Finish')]
    [String]$QueuePhase,

    [Parameter(HelpMessage = 'The path of the script to run when the task is triggered.')]
    [ValidateNotNullOrEmpty()]
    [String]$ScriptPath = $MyInvocation.PSCommandPath,

    [switch]$OnlyOnRebootRequired = $false,

    [switch]$ForceReboot = $false
) {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [Boolean]$Local:RequiresReboot = (Get-RebootFlag).Required() -or $ForceReboot;
        if ($OnlyOnRebootRequired -and (-not $Local:RequiresReboot)) {
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
            $Local:AdditionalArgs += '-WhatIf';
        }
        if ($VerbosePreference -ne 'SilentlyContinue') {
            $Local:AdditionalArgs += '-Verbose';
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

            Invoke-Timeout `
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

#endregion - Queue Functions

#region - Phase Functions

function Invoke-Phase_PreInit {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        Invoke-EnsureLocalScript;
        Sync-Time;

        # Sync time if not already done then restart if time was out of sync.
        # Turn off Sleep when off power but let screen turn off.
    }
}

function Invoke-Phase_SetupWindows {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [String[]]$Local:ScreenSteps;

        $Local:WindowsVersion = [System.Environment]::OSVersion.Version;
        switch ($Local:WindowsVersion.Major) {
            10 {
                Invoke-Info 'Windows 10 detected, continuing...';
                [String]$Local:Manufacturer = (Get-CimInstance -Class Win32_ComputerSystem).Manufacturer;

                Add-Type -AssemblyName System.Windows.Forms;
                Add-Type -AssemblyName Microsoft.VisualBasic;

                # Windows 10 Setup screen raw inputs
                # enter                                             - Language
                # down,enter,enter                                  - Keyboard
                # tab,tab,tab,enter                                 - Skip Network Setup
                # tab,tab,tab,tab,tab,tab,enter                     - Skip Second Network Setup
                # tab,tab,tab,tab,enter                             - Terms and Conditions
                # localadmin,enter,enter                            - Create Local Account
                # enter                                             - Permissions
                # shift+tab,enter                                   - Disable Cortana
                # tab,tab,tab,tab,tab,enter,tab,tab,tab,tab,enter   - Skip HP Bullshit

                # Activate the Setup Window to allow for keyboard input
                [Int]$Local:SetupPID = Get-Process -Name WWAHost | Select-Object -ExpandProperty Id -First 1;

                if ($null -eq $Local:SetupPID) {
                    Invoke-Error 'Failed to find the Windows Setup process';
                    Invoke-FailedExit -ExitCode $Script:FAILED_SETUP_ENVIRONMENT;
                }

                [Microsoft.VisualBasic.Interaction]::AppActivate($Local:SetupPID) | Out-Null;

                [String[]]$Local:ScreenSteps = @(
                    '{ENTER}', # Accept Region
                    '{DOWN}{ENTER}{ENTER}', # Select and confirm US Keyboard
                    '+{TAB}{ENTER}', # Skip Network Setup
                    '+{TAB}{ENTER}', # Skip Second Network Setup
                    '{TAB}{TAB}{TAB}{TAB}{ENTER}', # Terms and Conditions
                    'localadmin{ENTER}{ENTER}', # Create Local Account
                    '{ENTER}+{TAB}{ENTER}', # Privacy Settings
                    '+{TAB}{ENTER}' # No Cortana
                );

                switch ($Local:Manufacturer) {
                    'HP' {
                        $Local:ScreenSteps += '{ENTER}';
                        $Local:ScreenSteps += '{ENTER}';
                    }
                    default {
                        # Do nothing.
                    }
                }
            }
            default {
                Invoke-Error "This script is only supported on Windows 10, not Windows $($Local:WindowsVersion.Major)";
                Invoke-FailedExit -ExitCode $Script:FAILED_SETUP_ENVIRONMENT;
            }
        }

        $Local:ScreenSteps | ForEach-Object {
            Start-Sleep -Seconds 1;
            [System.Windows.Forms.SendKeys]::SendWait($_);
        }

        return $null;
    }
}

# Configure items like device name from the setup the user provided.
function Invoke-PhaseConfigure([Parameter(Mandatory)][ValidateNotNullOrEmpty()][PSCustomObject]$InstallInfo) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:NextPhase; }

    process {
        $InstallInfo | Assert-NotNull -Message 'Install info was null';

        #region - Device Name
        [String]$Local:DeviceName = $InstallInfo.DeviceName;
        $Local:DeviceName | Assert-NotNull -Message 'Device name was null';

        [String]$Local:ExistingName = $env:COMPUTERNAME;
        $Local:ExistingName | Assert-NotNull -Message 'Existing name was null'; # TODO :: Alternative method of getting existing name if $env:COMPUTERNAME is null

        if ($Local:ExistingName -eq $Local:DeviceName) {
            Invoke-Info "Device name is already set to $Local:DeviceName.";
        } else {
            Invoke-Info "Device name is not set to $Local:DeviceName, setting it now...";
            Rename-Computer -NewName $Local:DeviceName;
            (Get-RebootFlag).Set($null);
        }
        #endregion - Device Name

        #region - Auto-Login
        [String]$Local:RegKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon';
        try {
            $ErrorActionPreference = 'Stop';

            Set-ItemProperty -Path $Local:RegKey -Name 'AutoAdminLogon' -Value 1 | Out-Null;
            Set-ItemProperty -Path $Local:RegKey -Name 'DefaultUserName' -Value 'localadmin' | Out-Null;
            Set-ItemProperty -Path $Local:RegKey -Name 'DefaultPassword' -Value '' | Out-Null;

            Invoke-Info 'Auto-login registry keys set.';
        } catch {
            Invoke-Error 'Failed to set auto-login registry keys';
            Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:FAILED_REGISTRY;
        }
        #endregion - Auto-Login

        [String]$Local:NextPhase = 'Cleanup';
        return $Local:NextPhase;
    }
}

function Invoke-PhaseCleanup {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:NextPhase; }

    process {
        # function Invoke-Info {
        #     Param([String]$Message) Write-Host -ForegroundColor Green "INFO: $Message";
        # }
        # function Invoke-Error {
        #     Param([String]$Message) Write-Host -ForegroundColor Red "ERROR: $Message";
        # }
        # function Invoke-Verbose {
        #     Param([String]$Message) Write-Host -ForegroundColor Yellow "VERBOSE: $Message";
        # }
        # function Invoke-Warn {
        #     Param([String]$Message) Write-Host -ForegroundColor Yellow "WARN: $Message";
        # }
        # function Invoke-Debug {
        #     Param([String]$Message) Write-Host -ForegroundColor Cyan "DEBUG: $Message";
        # }
        # function Enter-Scope { }
        # function Exit-Scope { }
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

            Write-Progress -Activity $Local:ProgressActivity -CurrentOperation 'Getting items...' -PercentComplete 0;
            Write-Debug 'Getting items';
            [Object[]]$Local:InputItems = $GetItems.InvokeReturnAsIs();
            Write-Progress -Activity $Local:ProgressActivity -PercentComplete 10;

            if ($null -eq $Local:InputItems -or $Local:InputItems.Count -eq 0) {
                Write-Progress -Activity $Local:ProgressActivity -Status 'No items found.' -PercentComplete 100 -Completed;
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
                    $ErrorActionPreference = 'Stop';
                    $ProcessItem.InvokeReturnAsIs($Local:Item);
                } catch {
                    Invoke-Warn "Failed to process item [$Local:ItemName]";
                    Invoke-Debug -Message "Due to reason - $($_.Exception.Message)";
                    try {
                        $ErrorActionPreference = 'Stop';

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
            [CmdletBinding(SupportsShouldProcess)]
            param()

            begin { Enter-Scope; }
            end { Exit-Scope; }

            process {
                [String[]]$Services = @('HotKeyServiceUWP', 'HPAppHelperCap', 'HP Comm Recover', 'HPDiagsCap', 'HotKeyServiceUWP', 'LanWlanWwanSwitchingServiceUWP', 'HPNetworkCap', 'HPSysInfoCap', 'HP TechPulse Core');

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

                            if ($PSCmdlet.ShouldProcess("Stopping service [$($Local:Instance.Name)]")) {
                                $Local:Instance | Stop-Service -Force -Confirm:$false;
                                Invoke-Info "Stopped service $Local:Instance";
                            }
                        } catch {
                            Invoke-Info -Message "Failed to stop $Local:Instance";
                        }

                        Invoke-Info "Disabling service $ServiceName...";
                        try {
                            $ErrorActionPreference = 'Stop';

                            if ($PSCmdlet.ShouldProcess("Disabling service [$($Local:Instance.Name)]")) {
                                $Local:Instance | Set-Service -StartupType Disabled -Confirm:$false;
                                Invoke-Info "Disabled service $ServiceName";
                            }
                        } catch {
                            Invoke-Warn "Failed to disable $ServiceName";
                            Invoke-Debug -Message "Due to reason - $($_.Exception.Message)";
                        }
                    }
                };
            }
        }
        function Remove-Programs_HP {
            [CmdletBinding(SupportsShouldProcess)]
            param()

            begin { Enter-Scope; }
            end { Exit-Scope; }

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
                    'HP Device Access Manager'
                    'HP Client Security Manager'
                    'HP Connection Optimizer'
                    'HP Documentation'
                    'HP MAC Address Manager'
                    'HP Notifications'
                    'HP System Info HSA Service'
                    'HP Security Update Service'
                    'HP System Default Settings'
                    'HP Sure Click'
                    'HP Sure Click Security Browser'
                    'HP Sure Run'
                    'HP Sure Run Module'
                    'HP Sure Recover'
                    'HP Sure Sense'
                    'HP Sure Sense Installer'
                    'HP Wolf Security'
                    'HP Wolf Security - Console'
                    'HP Wolf Security Update Service'
                    'HP Wolf Security Application Support for Sure Sense'
                    'HP Wolf Security Application Support for Windows'
                    'HP Wolf Security Application Support for Chrome'
                );

                Invoke-Progress `
                    -GetItems { Get-Package | Where-Object { $UninstallablePrograms -contains $_.Name -or $Programs -contains $_.Name } } `
                    -GetItemName { Param([Microsoft.PackageManagement.Packaging.SoftwareIdentity]$Program) $Program.Name; } `
                    -ProcessItem {
                    Param([Microsoft.PackageManagement.Packaging.SoftwareIdentity]$Program)

                    $Local:Product = Get-CimInstance -Query "SELECT * FROM Win32_Product WHERE Name = '$($Program.Name)'";
                    if (-not $Local:Product) {
                        throw "Can't find MSI Package for program [$($Program.Name)]";
                    } else {
                        if ($PSCmdlet.ShouldProcess("Removing MSI program [$($Local:Product.Name)]")) {
                            msiexec /x $Local:Product.IdentifyingNumber /quiet /noreboot | Out-Null;
                            Invoke-Info "Sucessfully removed program [$($Local:Product.Name)]";
                        }
                    }
                };
            }
        }
        function Remove-ProvisionedPackages_HP {
            [CmdletBinding(SupportsShouldProcess)]
            param()

            begin { Enter-Scope; }
            end { Exit-Scope; }

            process {
                [String]$HPIdentifier = 'AD2F1837';

                Invoke-Progress -GetItems { Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -match "^$HPIdentifier" } } -ProcessItem {
                    Param($Package)

                    if ($PSCmdlet.ShouldProcess("Removing provisioned package [$($Package.DisplayName)]")) {
                        Remove-AppxProvisionedPackage -PackageName $Package.PackageName -Online -AllUsers | Out-Null;
                        Invoke-Info "Sucessfully removed provisioned package [$($Package.DisplayName)]";
                    }
                }
            }
        }
        # FIXME - After updating to win11 there is a new package that needs to be removed, how fun.
        function Remove-AppxPackages_HP {
            [CmdletBinding(SupportsShouldProcess)]
            param()

            begin { Enter-Scope; }
            end { Exit-Scope; }

            process {
                [String]$HPIdentifier = 'AD2F1837';

                Invoke-Progress -GetItems { Get-AppxPackage -AllUsers | Where-Object { $_.Name -match "^$HPIdentifier" } } -ProcessItem {
                    Param($Package)

                    if ($PSCmdlet.ShouldProcess("Removing appx-package [$($Package.Name)]")) {
                        Remove-AppxPackage -Package $Package.PackageFullName -AllUsers;
                        Invoke-Info "Sucessfully removed appx-package [$($Package.Name)]";
                    }
                };
            }
        }
        function Remove-Drivers_HP {
            [CmdletBinding(SupportsShouldProcess)]
            param()

            begin { Enter-Scope; }
            end { Exit-Scope; }

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

                        if ($PSCmdlet.ShouldProcess("Uninstalling driver [$Local:FileName]")) {
                            pnputil /delete-driver $Local:FileName /uninstall /force | Out-Null;
                            Invoke-Info "Removed driver: [$Local:FileName]";
                        }
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
                        KIND   = 'String';
                        Values = @{
                            1 = 'SWC\HPA000C'
                            2 = 'SWC\HPIC000C'
                            3 = 'SWC\HPTPSH000C'
                            4 = 'ACPI\HPIC000C'
                        };
                    };
                    'HKLM:\Software\Policies\Microsoft\Windows\DeviceInstall\Restrictions'               = @{
                        KIND   = 'DWORD';
                        Values = @{
                            DenyDeviceIDs            = 1;
                            DenyDeviceIDsRetroactive = 1;
                        };
                    };
                }.GetEnumerator() | ForEach-Object {
                    [String]$Local:RegistryPath = $_.Key;
                    [HashTable]$Local:RegistryTable = $_.Value;

                    If (-not (Test-Path $Local:RegistryPath)) {
                        if ($PSCmdlet.ShouldProcess("Creating registry path [$Local:RegistryPath]")) {
                            New-Item -Path $Local:RegistryPath -Force | Out-Null;
                        }
                    } else {
                        Invoke-Info "Registry path [$Local:RegistryPath] already exists, skipping creation...";
                    }

                    $Local:RegistryTable.Values.GetEnumerator() | ForEach-Object {
                        [String]$Local:ValueName = $_.Key;
                        [String]$Local:ValueData = $_.Value;

                        If (-not (Test-Path "$Local:RegistryPath\$Local:ValueName")) {

                            if ($PSCmdlet.ShouldProcess("Creating registry value [$Local:ValueName] with data [$Local:ValueData] in path [$Local:RegistryPath]")) {
                                New-ItemProperty -Path $Local:RegistryPath -Name $Local:ValueName -Value $Local:ValueData -PropertyType $Local:RegistryTable.KIND | Out-Null;
                                Invoke-Info "Created registry value [$Local:ValueName] with data [$Local:ValueData] in path [$Local:RegistryPath]";
                            }
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
        Remove-Drivers_HP;

        (Get-RebootFlag).Set($null);

        [String]$Local:NextPhase = 'Install';
        return $Local:NextPhase;
    }
}

# Install the agent and any other required software.
# TODO :: Maybe use the feature log files to determine whats being installed and if it finished?
function Invoke-PhaseInstall([Parameter(Mandatory)][ValidateNotNullOrEmpty()][PSCustomObject]$InstallInfo) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:NextPhase; }

    process {
        [String]$Local:AgentServiceName = 'Advanced Monitoring Agent';
        [String]$Local:NextPhase = 'Update';

        # Check if the agent is already installed and running.
        if (Get-Service -Name $Local:AgentServiceName -ErrorAction SilentlyContinue) {
            Invoke-Info 'Agent is already installed, skipping installation...';
            return $Local:NextPhase;
        }

        Invoke-WithinEphemeral {
            [String]$Local:ClientId = $InstallInfo.ClientId;
            [String]$Local:SiteId = $InstallInfo.SiteId;
            [String]$Local:Uri = "https://system-monitor.com/api/?apikey=${ApiKey}&service=get_site_installation_package&endcustomerid=${ClientId}&siteid=${SiteId}&os=windows&type=remote_worker";

            Invoke-Info "Downloading agent from [$Local:Uri]";
            try {
                $ErrorActionPreference = 'Stop';
                Invoke-WebRequest -Uri $Local:Uri -OutFile 'agent.zip' -UseBasicParsing;
            } catch {
                Invoke-Error "Failed to download agent from [$Local:Uri]";
                Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:AGENT_FAILED_DOWNLOAD;
            }

            Invoke-Info 'Expanding archive...';
            try {
                $ErrorActionPreference = 'Stop';

                Expand-Archive -Path 'agent.zip' -DestinationPath $PWD -Force | Out-Null;
            } catch {
                Invoke-Error 'Failed to expand archive';
                Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:AGENT_FAILED_EXPAND;
            }

            Invoke-Info 'Finding agent executable...';
            try {
                $ErrorActionPreference = 'Stop';

                [String]$Local:OutputExe = Get-ChildItem -Path $PWD -Filter '*.exe' -File;
                $Local:OutputExe | Assert-NotNull -Message 'Failed to find agent executable';
            } catch {
                Invoke-Info 'Failed to find agent executable';
                Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:AGENT_FAILED_FIND;
            }

            Invoke-Info "Installing agent from [$Local:OutputExe]...";
            try {
                $ErrorActionPreference = 'Stop';

                [System.Diagnostics.Process]$Local:Installer = Start-Process -FilePath $Local:OutputExe -Wait -PassThru;
                $Local:Installer.ExitCode | Assert-Equal -Expected 0 -Message "Agent installer failed with exit code [$($Local:Installer.ExitCode)]";

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
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:NextPhase; }

    process {
        [String]$Local:NextPhase = if ($RecursionLevel -ge 2) { 'Finish' } else { 'Update' };

        Get-WindowsUpdate -Install -AcceptAll -AutoReboot:$false -IgnoreReboot -IgnoreUserInput -Confirm:$false | Out-Null;
        (Get-RebootFlag).Set($null);

        return $Local:NextPhase;
    }
}

function Invoke-PhaseFinish {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:NextPhase; }

    process {
        [String]$Local:NextPhase = $null;

        #region - Remove localadmin Auto-Login
        $Local:RegKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon';
        try {
            $ErrorActionPreference = 'Stop';

            Remove-ItemProperty -Path $Local:RegKey -Name 'AutoAdminLogon' -Force -ErrorAction Stop;
            Remove-ItemProperty -Path $Local:RegKey -Name 'DefaultUserName' -Force -ErrorAction Stop;
            Remove-ItemProperty -Path $Local:RegKey -Name 'DefaultPassword' -Force -ErrorAction Stop;
        } catch {
            Invoke-Error 'Failed to remove auto-login registry keys';
            Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:FAILED_REGISTRY;
        }
        #endregion - Remove localadmin Auto-Login

        return $Local:NextPhase;
    }
}

#endregion - Phase Functions

Invoke-RunMain $PSCmdlet {
    Register-ExitHandler -Name 'Running Flag Removal' -ExitHandler {
        (Get-RunningFlag).Remove();
    };

    Register-ExitHandler -Name 'Queued Task Removal' -OnlyFailure -ExitHandler {
        Remove-QueuedTask;
    };

    # Ensure only one process is running at a time.
    If ((Get-RunningFlag).IsRunning()) {
        Invoke-Error 'The script is already running in another session, exiting...';
        Exit $Script:ALREADY_RUNNING;
    } else {
        (Get-RunningFlag).Set($null);
        Remove-QueuedTask;
    }

    # TODO - Find a way to queue the next phase after the setup is complete.
    if ($Phase -eq 'SetupWindows') {
        Invoke-Phase_SetupWindows;
        return;
    }

    Invoke-Phase_PreInit;

    Invoke-EnsureLocalScript;
    Invoke-EnsureNetwork -Name $NetworkName -Password $NetworkPassword;

    # FIXME - Temporary fix
    $Local:CurrentReadLine = Get-Module 'PSReadLine';
    if ($null -eq $Local:CurrentReadLine -or $Local:CurrentReadLine.Version -lt [Version]::Parse('2.1.0')) {
        Invoke-Info 'Updating PSReadLine module';

        $null = Install-PackageProvider NuGet -MinimumVersion 2.8.5.201 -Force;
        $null = Set-PSRepository PSGallery -InstallationPolicy Trusted;
        $null = Install-Module -Name 'PSReadLine' -MinimumVersion '2.3.4' -Force;
        try {
            $null = Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction SilentlyContinue;
        } catch {
            # It actually did succeed, but it throws an error.
        }

        Add-QueuedTask -QueuePhase $Phase -ForceReboot:$False;
        Invoke-QuickExit;
    }

    Update-ToWin11;

    $Local:InstallInfo = Get-InstallInfo;

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
        Invoke-Info 'No next phase was returned, exiting...';
        return
    }

    Invoke-Info "Queueing next phase [$Local:NextPhase]...";
    Add-QueuedTask -QueuePhase $Local:NextPhase;
}
