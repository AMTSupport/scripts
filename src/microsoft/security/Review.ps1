#Requires -Version 7.1

class SecurityScore {
    [Double]$Before;
    [Double]$After;

    [String[]]$Changes;

    SecurityScore() {
        $this.Before = 0;
        $this.After = 0;
        $this.Changes = @();
    }
}

class MailSecurity {
    [Boolean]$Enabled;
    [Boolean]$AllowList;
    [Boolean]$BlockList;
    [Boolean]$AllowListOnly;
    [Boolean]$BlockListOnly;
    [Boolean]$AllowListAndBlockList;

    MailSecurity() {
        $this.Enabled = $false;
        $this.AllowList = $false;
        $this.BlockList = $false;
        $this.AllowListOnly = $false;
        $this.BlockListOnly = $false;
        $this.AllowListAndBlockList = $false;
    }
}

function Complete-Template(
    [SecurityScore]$SecurityScore
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
@"
Microsoft 365 Secure score
$(if ($SecurityScore.Before -ne $SecurityScore.After) {
    "Security score has changed from ${SecurityScore.Before} to ${SecurityScore.After}."
} else {
    "Security score has not changed, remaining at ${SecurityScore.Before}."
})
$(if ($SecurityScore.Changes.Count -gt 0) {
    "Changes:"
    foreach ($Local:Change in $SecurityScore.Changes) {
        " - $Local:Change"
    }
} else {
    "No changes."
})

Mail Security
[changes]

Impersonation review
[x] Domain impersonation attempts since past review
[x] User impersonation attempts since past review - all quarantined

Newly registered Devices
[x] changes to devices.

Multifactor mobile number changes
[x] changes in MFA

Manual review of alerts
MCAS:
All connected apps are [status]
[x] Open alerts
[Security Centre Alerts:
[x]

Review sign-in activity
[x] large volume of logins.
[All accepted from local address]
[No strange logins noted.]

Cloud backup
Datto Checked - [x] issues.
One Drive [x/x]
Exchange [x/x]
Sharepoint [x/x]
Teams [x/x]
All completed over last [x] days.

Test sent to Alerts mailbox
Test [not] successfully received in AMT Helpdesk
"@
    }
}

Import-Module $PSScriptRoot/../../common/Environment.psm1;
Invoke-RunMain $MyInvocation {

};
