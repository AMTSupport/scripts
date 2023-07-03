<#
Checks if the current user is localadmin
Phil Haddock 19th May 2023
#>

$Ver = "v1.05:"

$admins = net localgroup administrators
$AdminTrue = $false

for ($i = 6; $i -lt $admins.Length-2;$i++)

{
If ($admins[$i] -notin ("localadmin","nt authority\\system","administrator"))
{
$AdminTrue = $true
$AdminUser = $admins[$i]


}
}

If ($AdminTrue = $true)
{
Write-Host $Ver User $AdminUser is localadmin
Exit 1001
}
else
{
Write-Host $Ver Users not found to be local administrators
Exit 0
}