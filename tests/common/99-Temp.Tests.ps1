BeforeDiscovery {
    Import-Module $PSScriptRoot/../../src/common/00-Environment.psm1;
    Import-CommonModules;
}

AfterAll {
    Remove-CommonModules;
}
