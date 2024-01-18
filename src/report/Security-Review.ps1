#Requires -Version 7.1
#Requires -Modules MCAS

Import-Module ../common/Environment.psm1;

#region - Types

class TemplateFiller {
    [String]$Template;

    TemplateFiller([String]$Template) {
        $this.Template = $Template;
    }

    [String]Fill([PSCustomObject]$Object) {
        $Local:Template = $this.Template;

        foreach ($Local:Property in $Object.PSObject.Properties) {
            $Local:Template = $Local:Template.Replace("{{$($Local:Property.Name)}}", $Local:Property.Value);
        }

        return $Local:Template;
    }
}

class SecurityReviewReport {
    [SecurityScoreReport]$SecurityScore;
    [MailSecurityReport]$MailSecurity;
    [ImmpersonationReport]$Impersonations;
    [DeviceChangesReport]$DeviceChanges;
    [MultiFactorAuthReport]$MultiFactorAuth;
}

class SecurityScoreReport {
    [Int]$Before;
    [Int]$After;

    [SecurityScoreChange[]]$Changes;
}

class SecurityScoreChange {
    [String]$Name;
    [Int]$Increase;
}

class MailSecurityReport {
    [String[]]$Changes;
}

class ImmpersonationReport {
    [Immpersonation[]]$Changes;
}

Class Immpersonation {
    [String]$ImpersonatedUser;
    [String]$ImpersonatedBy;
}

class DeviceChangesReport {
    [DeviceChange[]]$Changes;
}

class DeviceChange {
    [String]$DeviceName;
    [ChangeType]$ChangeType;
    [String]$ChangedBy;
}

enum ChangeType {
    Added;
    Removed;
}

class MultiFactorAuthReport {
    [MultiFactorUser[]]$Changes;
}

class MultiFactorUser {
    [String]$User;
    [AuthMethod]$AuthMethod;
}

enum AuthMethod {
    None;
    Phone;
    App;
}

#endregion - Types

function Format-Report(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [PSCustomObject]$Report
) {
    begin { Local:Enter-Scope -Invocation $MyInvocation; }
    end { Local:Exit-Scope -Invocation $MyInvocation; }

    process {
        # Format the report into a table
    }
}

Invoke-RunMain $MyInvocation {

};
