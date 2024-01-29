BeforeDiscovery {
    Import-Module $PSScriptRoot/../../src/common/Environment.psm1;
    Import-CommonModules;
}

AfterAll {
    Remove-CommonModules;
}


Describe "99-Flag.psm1 Tests" {
    Context ""
}
