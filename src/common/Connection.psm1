Using module .\Logging.psm1
Using module .\Scope.psm1
Using module .\Exit.psm1
Using module .\Input.psm1
Using module Microsoft.Graph.Authentication
Using module ExchangeOnlineManagement

$Script:ExchangeSessionId;
$Script:IPPSSessionId;

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
        $RemoveKeys = @();
        $Params.GetEnumerator() | Where-Object { $null -eq $_.Value } | ForEach-Object {
            $RemoveKeys = $RemoveKeys + $_.Key;
        }
        $RemoveKeys | ForEach-Object { $Params.Remove($_); }
        Invoke-Debug "Invoking Expression '$FunctionName $($Params.GetEnumerator() | ForEach-Object { "-$($_.Key):$($_.Value)" })'";
        & $FunctionName @Params;
    };
}

$Script:Services = @{
    ExchangeOnline     = @{
        Matchable  = $True;
        Context    = {
            if ($Script:ExchangeSessionId) {
                Get-ConnectionInformation -ConnectionId:$Script:ExchangeSessionId | Select-Object -ExpandProperty UserPrincipalName;
            } else {
                $null;
            }
        };
        Connect    = { param($AccessToken)
            Invoke-NonNullParams 'Connect-ExchangeOnline' ($PSBoundParameters + @{ ShowBanner = $False });
            $Script:ExchangeSessionId = Get-ConnectionInformation | Select-Object -Last 1 -ExpandProperty ConnectionId;
        };
        Disconnect = { Disconnect-ExchangeOnline -Confirm:$False };
    };
    SecurityComplience = @{
        Matchable  = $True;
        Context    = {
            if ($Script:IPPSSessionId) {
                Get-ConnectionInformation -ConnectionId:$Script:IPPSSessionId | Select-Object -ExpandProperty UserPrincipalName;
            } else {
                $null;
            }
        };
        Connect    = {
            Connect-IPPSSession -ShowBanner:$False;
            $Script:IPPSSessionId = Get-ConnectionInformation | Select-Object -Last 1 -ExpandProperty ConnectionId;
        };
        Disconnect = { Disconnect-ExchangeOnline -Confirm:$False; };
    };
    Graph              = @{
        Matchable  = $True;
        Context    = {
            try {
                Get-MgContext | Select-Object -ExpandProperty Account;
            } catch {
                $null;
            }
        };
        Connect    = { param($Scopes, $AccessToken)
            if ($AccessToken) {
                Connect-MgGraph -AccessToken:$AccessToken -NoWelcome -ContextScope Process;

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

            try {
                $Local:Context = Get-MgContext;
            } catch { }

            if (-not $Local:Context) {
                Connect-MgGraph -Scopes:$Scopes -NoWelcome -ContextScope Process;
            }
        };
        Disconnect = { Disconnect-MgGraph };
        IsValid    = {
            param([String[]]$Scopes)

            try {
                $Local:Context = Get-MgContext;
            } catch {
                return $False;
            }

            if ($Scopes) {
                Invoke-Debug 'Checking if connected to Graph with required scopes...';
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
        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'Graph')]
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
        } catch {
            Invoke-FailedExit -ExitCode $Script:ERROR_CANT_DISCONNECT -FormatArgs @($Local:Service) -ErrorRecord $_;
        }
    }
}

function Local:Connect-ServiceInternal {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'Graph')]
        [String]$Service,

        [Parameter()]
        [String[]]$Scopes,

        [Parameter()]
        [SecureString]$AccessToken
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        try {
            if ($PSCmdlet.ShouldProcess("Connect to $Local:Service")) {
                $null = & $Script:Services[$Local:Service].Connect -Scopes:$Scopes -AccessToken:$AccessToken;
            }
        } catch {
            Invoke-FailedExit -ExitCode $Script:ERROR_COULDNT_CONNECT -FormatArgs @($Local:Service) -ErrorRecord $_;
        }
    }
}

function Local:Get-ServiceContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'Graph')]
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
        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'Graph')]
        [String]$Service
    )

    $null -ne (Get-ServiceContext -Service $Service);
}

function Local:Test-IsMatchable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'Graph')]
        [String]$ServiceA,

        [Parameter()]
        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'Graph')]
        [String]$ServiceB
    )

    $Script:Services[$Service].Matchable -and (-not $ServiceB -or $Script:Services[$ServiceB].Matchable);
}

function Local:Test-SameContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'Graph')]
        [String]$ServiceA,

        [Parameter(Mandatory)]
        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'Graph')]
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
        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'Graph')]
        [String]$ServiceA,

        [Parameter(Mandatory)]
        [ValidateSet('ExchangeOnline', 'SecurityComplience', 'Graph')]
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
    [ValidateSet('ExchangeOnline', 'SecurityComplience', 'Graph')]
    [String[]]$Services,

    [Parameter()]
    [String[]]$Scopes,

    [Parameter()]
    [SecureString]$AccessToken,

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
            try {
                [String]$Local:Context = Get-ServiceContext -Service $Local:Service;
            } catch {
                Invoke-Debug "Failed to get connection information for $Local:Service";
                Format-Error -InvocationInfo $_.InvocationInfo;
            }

            # FIXME
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
                Invoke-FailedExit -ExitCode:$Script:ERROR_NOT_CONNECTED -FormatArgs @($Local:Service) -ErrorRecord $_;
            }

            while ($True) {
                try {
                    if ($AccessToken) { Invoke-Info "Connecting to $Local:Service with access token..."; }
                    else { Invoke-Info "Connecting to $Local:Service..."; }
                    Invoke-Verbose "Scopes: $($Scopes -join ', ')";

                    Connect-ServiceInternal -Service:$Local:Service -Scopes:$Scopes -AccessToken:$AccessToken;
                } catch {
                    Invoke-FailedExit -ExitCode $Script:ERROR_COULDNT_CONNECT -FormatArgs @($Local:Service) -ErrorRecord $_;
                }

                if ($Local:LastService) {
                    Invoke-Info 'Checking if all services are connected with the same account...';
                    Invoke-Info "Service A: $Local:Service";
                    Invoke-Info "Service B: $Local:LastService";

                    if ($Local:Account -and (Test-NotMatchableOrSameContext -ServiceA:$Local:Service -ServiceB:$Local:LastService)) {
                        Invoke-Warn 'Not all services are connected with the same account, please reconnect with the same account.';
                        Disconnect-ServiceInternal -Service $Local:Service;
                        continue;
                    }
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
