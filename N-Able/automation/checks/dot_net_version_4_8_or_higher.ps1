if ($Result = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\' | Get-ItemPropertyValue -Name Release | Foreach-Object { $_ -ge 528040} )
{
write-host Dot Net Version is greater or equal to 4.8
}
Else
{
Write-Host Dot Net version does not comply
}