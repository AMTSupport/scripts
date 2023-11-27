function Connect-Service(
    [Parameter(Mandatory)]
    [ValidateSet('ExchangeOnline', 'SecurityComplience', 'AzureAD')]
    [String]$Service,

    # If true prompt for confirmation if already connected.
    [Switch]$Confirm
) {
    $Connected = switch ($Service) {
        'ExchangeOnline' {
            Get-ConnectionInformation | Select-Object -ExpandProperty UserPrincipalName;
        }
        'SecurityComplience' {
            Get-IPPSSession | Select-Object -ExpandProperty UserPrincipalName;
        }
        'AzureAD' {
            Get-AzureADCurrentSessionInfo | Select-Object -ExpandProperty Account;
        }
    }

    if ($Connected) {
        if ($Confirm) {
            $Local:Continue = Get-UserConfirmation -Title "Already connected to $Service as [$Connected]" -Question 'Do you want to continue?' -DefaultChoice $true;
            if (-not $Local:Continue) {
                return;
            }
        } else {
            Write-Verbose "Already connected to $Service. Skipping..."
            return
        }
    }

    try {
        switch ($Service) {
            'ExchangeOnline' {
                Connect-ExchangeOnline;
            }
            'SecurityComplience' {
                Connect-IPPSSession;
            }
            'AzureAD' {
                Connect-AzureAD;
            }
        }
    } catch {
        Write-Error "Failed to connect to $Service";
        exit 1002;
    }
}
