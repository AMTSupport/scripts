@{
    RootModule = 'AMT.PowerShell.Common.dll'
    ModuleVersion = '0.1.0'
    GUID = 'b1fd7d3d-5f6d-4f6d-8d7b-5d7e6c7b0b23'
    Author = 'Applied Marketing Technologies'
    CompanyName = 'Applied Marketing Technologies'
    Copyright = '(c) Applied Marketing Technologies. All rights reserved.'
    Description = 'Repo-local PowerShell binary module scaffold.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    CmdletsToExport = @(
        'Assert-Equal',
        'Assert-NotNull',
        'Get-AMTModuleInfo',
        'Get-Flag',
        'Get-FlagPath',
        'Get-LastSyncTime',
        'Get-LockPath',
        'Get-NamedTempFolder',
        'Get-RebootFlag',
        'Get-RunningFlag',
        'Get-UniqueTempFolder',
        'Initialize-AMTCompiledRuntime',
        'Invoke-UnderLock',
        'Invoke-WithinEphemeral',
        'Release-LockFile',
        'Sync-Time',
        'Wait-LockFile'
    )
    VariablesToExport = @()
    AliasesToExport = @()
}
