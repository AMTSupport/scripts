function Connect-Service(
    [Parameter(Mandatory)]
    [ValidateSet('ExchangeOnline', 'SecurityComplience', 'AzureAD')]
    [String]$Service,

    # If true prompt for confirmation if already connected.
    [Switch]$Confirm
) {
    $Local:Connected = try {
        switch ($Service) {
            'ExchangeOnline' {
                # if (!(Get-PSSession | Where-Object { $_.Name -match 'ExchangeOnline' -and $_.Availability -eq 'Available' })) { Connect-ExchangeOnline }
                Get-ConnectionInformation -ErrorAction SilentlyContinue | Select-Object -ExpandProperty UserPrincipalName;
            }
            'SecurityComplience' {
                Get-IPPSSession -ErrorAction SilentlyContinue | Select-Object -ExpandProperty UserPrincipalName;
            }
            'AzureAD' {
                Get-AzureADCurrentSessionInfo -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Account;
            }
        }
    } catch {
        $null
    }

    if ($Local:Connected) {
        if ($Confirm) {
            $Local:Continue = Get-UserConfirmation -Title "Already connected to $Service as [$Local:Connected]" -Question 'Do you want to continue?' -DefaultChoice $true;
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
