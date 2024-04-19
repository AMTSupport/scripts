$Script:Services = @{
    ExchangeOnline = @{
        Matchable  = $True;
        Context    = { Get-ConnectionInformation | Select-Object -ExpandProperty UserPrincipalName; };
        Connect    = { Connect-ExchangeOnline -ShowBanner:$False };
        Disconnect = { Disconnect-ExchangeOnline -Confirm:$False };
    };
    SecurityComplience = @{
        Matchable  = $True;
        Context    = { Get-IPPSSession | Select-Object -ExpandProperty UserPrincipalName; };
        Connect    = { Connect-IPPSSession -ShowBanner:$False };
        Disconnect = { Disconnect-IPPSSession };
    };
    AzureAD = @{
        Matchable  = $True;
        Context    = { Get-AzureADCurrentSessionInfo | Select-Object -ExpandProperty Account; };
        Connect    = { Connect-AzureAD };
        Disconnect = { Disconnect-AzureAD };
    };
    Msol = @{
        Matchable  = $False;
        Context    = { Get-MsolCompanyInformation | Select-Object -ExpandProperty DisplayName; };
        Connect    = { Connect-MsolService };
        Disconnect = { Disconnect-MsolService };
    };
    Graph = @{
        Matchable  = $True;
        Context    = { Get-MgContext | Select-Object -ExpandProperty Account; };
        Connect    = { param([String[]]$Scopes) Connect-MgGraph -NoWelcome -Scopes:$Scopes; };
        Disconnect = { Disconnect-MgGraph };
        IsValid    = {
            param([String[]]$Scopes)

            $Local:Context = Get-MgContext;

            if ($null -eq $Local:Context) {
                return $False;
            }

            if ($Scopes) {
                Invoke-Debug "Checking if connected to Graph with required scopes...";
                Invoke-Debug "Required Scopes: $($Scopes -join ', ')";
                Invoke-Debug "Current Scopes: $($Local:Context.Scopes -join ', ')";

                [Bool]$Local:HasAllScopes = ($Scopes | Where-Object { $Local:Context.Scopes -notcontains $_; }).Count -eq 0;
            } else {
                $Local:HasAllScopes = $True;
            }

            $Local:HasAllScopes;
        }
    };
}

#startregion - Internal Functions
[Int]$Script:ERROR_CANT_DISCONNECT = Register-ExitCode -Description 'Failed to disconnect from {0}.';
function Local:Disconnect-ServiceInternal {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'AzureAD', 'Graph', 'Msol')]
        [String]$Service
    )

    Invoke-Info "Disconnecting from $Local:Service...";

    try {
        if ($PSCmdlet.ShouldProcess("Disconnect from $Local:Service")) {
            & $Script:Services[$Local:Service].Disconnect | Out-Null;
        };
    } catch {
        Invoke-FailedExit -ExitCode $Script:ERROR_CANT_DISCONNECT -FormatArgs @($Local:Service);
    }
}

[Int]$Script:ERROR_NOT_CONNECTED = Register-ExitCode -Description 'There was an error connecting to {0}, please try again.';
function Local:Connect-ServiceInternal {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'AzureAD', 'Graph', 'Msol')]
        [String]$Service,

        [Parameter()]
        [String[]]$Scopes
    )

    Invoke-Info "Connecting to $Local:Service...";
    Invoke-Verbose "Scopes: $($Scopes -join ', ')";

    try {
        if ($PSCmdlet.ShouldProcess("Connect to $Local:Service")) {
            $null = & $Script:Services[$Local:Service].Connect -Scopes:$Scopes;
        }
    } catch {
        Invoke-FailedExit -ExitCode $Script:ERROR_NOT_CONNECTED -FormatArgs @($Local:Service);
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
    } catch {
        # If we can't get the context, we're not connected.
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
#endregion

[Int]$Script:ERROR_NOT_CONNECTED = Register-ExitCode -Description 'Not connected to {0}, must be connected to continue.';
[Int]$Script:ERROR_COULDNT_CONNECT = Register-ExitCode -Description 'Failed to connect to {0}.';
[Int]$Script:ERROR_NOT_MATCHING_ACCOUNTS = Register-ExitCode -Description 'Not all services are connected with the same account, please ensure all services are connected with the same account.';
function Connect-Service(
    [Parameter(Mandatory)]
    [ValidateSet('ExchangeOnline', 'SecurityComplience', 'AzureAD', 'Graph', 'Msol')]
    [String[]]$Services,

    [Parameter()]
    [String[]]$Scopes,

    # If true don't prompt for confirmation if already connected.
    [Switch]$DontConfirm,

    # If true only check if connected, don't connect.
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
            } catch {
                Invoke-Debug "Failed to get connection information for $Local:Service";
                if ($Global:Logging.Debug) {
                    Format-Error -InvocationInfo $_.InvocationInfo;
                }
            }

            # if ($Local:LastService) {
            #     if (-not (Test-MatchableAndSameContext -ServiceA:$Local:Service -ServiceB:$Local:LastService)) {
            #         Invoke-Warn 'Not all services are connected with the same account, please reconnect with the same account.';
            #         Disconnect-ServiceInternal -Service $Local:Service;
            #     }
            # } else {

            # }


            if ($Local:LastService -and (Test-NotMatchableOrSameContext -ServiceA:$Local:Service -ServiceB:$Local:LastService)) {
                Invoke-Info 'Not all services are connected with the same account, forcing disconnect...';
                Disconnect-ServiceInternal -Service:$Local:Service;
            } elseif ($Local:Context) {
                [ScriptBlock]$Local:ValidCheck = $Script:Services[$Local:Service].IsValid;
                if ($Local:ValidCheck -and -not (& $Local:ValidCheck -Scopes:$Scopes)) {
                    Invoke-Info "Connected to $Local:Service, but missing required scopes. Disconnecting...";
                    Disconnect-ServiceInternal -Service $Local:Service;
                } elseif (!$DontConfirm) {
                    $Local:Continue = Get-UserConfirmation -Title "Already connected to $Local:Service as [$Local:Context]" -Question 'Do you want to continue?' -DefaultChoice $true;
                    if ($Local:Continue) {
                        Invoke-Verbose 'Continuing with current connection...';
                        $Local:Account = $Local:Context;
                        $Local:LastService = $Local:Service;
                        continue;
                    }

                    Disconnect-ServiceInternal -Service $Local:Service;
                } else {
                    Invoke-Verbose "Already connected to $Local:Service. Skipping...";
                    $Local:Account = $Local:Context;
                    $Local:LastService = $Local:Service;
                    continue
                }
            } elseif ($CheckOnly) {
                Invoke-FailedExit -ExitCode:$Script:ERROR_NOT_CONNECTED -FormatArgs @($Local:Service);
            }

            while ($True) {
                try {
                    Connect-ServiceInternal -Service $Local:Service -Scopes:$Scopes;
                } catch {
                    Invoke-FailedExit -ExitCode $Script:ERROR_COULDNT_CONNECT -FormatArgs @($Local:Service);
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
