Try {
$Version = get-itemproperty -Path Registry::'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\' -name Version
Write-Host Dot Net Version is $Version.Version
}
Catch {
Write-Host Version is not correct
}