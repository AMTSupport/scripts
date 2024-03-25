[Int]$Script:ERROR_NOT_CONNECTED = Register-ExitCode -Description 'Not connected to {0}, must be connected to continue.';
function Connect-Service(
    [Parameter(Mandatory)]
    [ValidateSet('ExchangeOnline', 'SecurityComplience', 'AzureAD', 'Graph', 'Msol')]
    [String[]]$Services,

    [Parameter()]
    [String[]]$Scopes,

    # If true don't prompt for confirmation if already connected.
    [Switch]$DontConfirm
) {
    foreach ($Local:Service in $Services) {
        Invoke-Info "Connecting to $Local:Service...";

        $Local:Connected = try {
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
                    $Local:Context = Get-MgContext;
                    if ($null -eq $Local:Context) {
                        $null;
                    } elseif ($Scopes) {
                        [Bool]$Local:HasAllScopes = ($Local:Context.Scopes | Where-Object { $Scopes -notcontains $_; }).Count -eq 0;
                        if ($Local:HasAllScopes) {
                            $Local:Context.Account;
                        } else {
                            $null;
                        }
                    } else {
                        $Local:Context.Account;
                    }

                    if ($Scopes) {
                        [Bool]$Local:HasAllScopes = (Get-MgContext | Select-Object -ExpandProperty Scopes | Where-Object { $Scopes -notcontains $_; }).Count -eq 0;
                    } else {
                        $Local:HasAllScopes = $False;
                    }

                    if ($Local:HasAllScopes) {
                        Get-MgContext | Select-Object -ExpandProperty Account;
                    } else {
                        Invoke-Warn 'Not all required scopes are present. Reconnecting...';
                        $null;
                    }
                }
                'Msol' {
                    Get-MsolCompanyInformation | Select-Object -ExpandProperty DisplayName;
                }
            }
        } catch {
            Invoke-Debug "Failed to get connection information for $Local:Service";
            if ($Global:Logging.Debug) {
                Invoke-FormattedError -InvocationInfo $_.InvocationInfo;
            }
        }

        if ($Local:Connected) {
            if (!$DontConfirm) {
                $Local:Continue = Get-UserConfirmation -Title "Already connected to $Local:Service as [$Local:Connected]" -Question 'Do you want to continue?' -DefaultChoice $true;
                if ($Local:Continue) {
                    Invoke-Verbose 'Continuing with current connection...';
                    continue;
                }

                switch ($Local:Service) {
                    'ExchangeOnline' {
                        Disconnect-ExchangeOnline -Confirm:$False;
                    }
                    'SecurityComplience' {
                        Disconnect-IPPSSession;
                    }
                    'AzureAD' {
                        Disconnect-AzureAD;
                    }
                    'Graph' {
                        Disconnect-MgGraph;
                    }
                    'Msol' {
                        Disconnect-MsolService;
                    }
                }
            } else {
                Invoke-Verbose "Already connected to $Local:Service. Skipping..."
                continue
            }
        } elseif ($CheckOnly) {
            Invoke-FailedExit -ExitCode:$Script:ERROR_NOT_CONNECTED -FormatArgs @($Local:Service);
        }

        try {
            Invoke-Info "Getting credentials for $Local:Service...";

            switch ($Local:Service) {
                'ExchangeOnline' {
                    Connect-ExchangeOnline -ShowBanner:$False;
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
