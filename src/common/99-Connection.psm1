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
        Info "Connecting to $Local:Service...";

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
                if (-not $Local:Continue) {
                    return;
                }

                Verbose 'Continuing with current connection...';
            } else {
                Verbose "Already connected to $Local:Service. Skipping..."
                return
            }
        }

        try {
            Info "Getting credentials for $Local:Service...";

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
