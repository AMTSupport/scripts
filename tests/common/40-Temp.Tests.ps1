BeforeDiscovery {
    $ModuleName = & $PSScriptRoot/Base.ps1;
}

AfterAll {
    Remove-CommonModules;
}
