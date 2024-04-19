$ExitCode = 0
$Hotfix=Get-HotFix -ComputerName $env:COMPUTERNAME|Measure-Object Installedon -Maximum|Select-Object Maximum
$Max=get-date -date $Hotfix.Maximum -format dd/MM/yyyy
$Max = $Max.ToString()
Write-Output $Max
if ((get-date -date $Hotfix.Maximum) -lt (get-date).AddDays(-30)) {$ExitCode = 1001}
exit $ExitCode
