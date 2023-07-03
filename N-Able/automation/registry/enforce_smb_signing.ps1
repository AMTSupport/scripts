<#
.SYNOPSIS
  Enforce SMB Signing




#>


# Parameters
Param (
#    [string]$ScriptLogLocation = "C:\Temp2",
#    [string]$LogFileName = "RemediatePrintNightmare.log",
    [string]$RegPath = "HKLM:\System\CurrentControlSet\Services\LanManServer\Parameters",
    [string]$ValueName = "RequireSecuritySignature",
    [string]$ValueType = "DWord",
    [string]$Value = "1",
    [string]$Result
)

function Test-RegistryValue {

param (
 [parameter(Mandatory=$true)]
 [ValidateNotNullOrEmpty()]$Path,

[parameter(Mandatory=$true)]
 [ValidateNotNullOrEmpty()]$Value
)

#write-host Starting function
#write-host Path $Path
#Write-Host $ValueName

try {

Get-ItemProperty -Path $Path -Name $ValueName -ErrorAction Stop|Out-Null
write-host True $Path
 return $true
 }

catch {

Write-Host false $Path
return $false

}

}

# Start Logging (path will be created if it doesn't already exist.  Doesn't work with RMM)
#Start-Transcript -Path (Join-Path $ScriptLogLocation $LogFileName) -Append

# Check if the registry key exists
#$KeyTest = Test-Path $RegPath
$KeyTest = Test-RegistryValue $RegPath $ValueName

if($KeyTest){
    # Update the value
    New-ItemProperty -Path $RegPath -Name $ValueName -Value $Value -PropertyType $ValueType -Force
    $Result="Key found: $valuename -Updated to $value"
}
else{
    # Add the registry key
    New-Item -Path $RegPath -Force
    # Create/update the value
    New-ItemProperty -Path $RegPath -Name $ValueName -Value $Value -PropertyType $ValueType -Force
    $Result="Key not found: $valuename -creating"
}

Write-Host $Result

$ValueName = "EnableSecuritySignature"

$KeyTest = Test-RegistryValue $RegPath $ValueName

if($KeyTest){
    # Update the value
    New-ItemProperty -Path $RegPath -Name $ValueName -Value $Value -PropertyType $ValueType -Force
    $Result="Key found: $valuename -Updated to 1"
}
else{
    # Add the registry key
    New-Item -Path $RegPath -Force
    # Create/update the value
    New-ItemProperty -Path $RegPath -Name $ValueName -Value $Value -PropertyType $ValueType -Force
    $Result="Key not found: $valuename -creating"
}

Write-Host $Result


$RegPath = "HKLM:\System\CurrentControlSet\Services\LanManWorkstation\Parameters"
$ValueName = "RequireSecuritySignature"

$KeyTest = Test-RegistryValue $RegPath $ValueName

if($KeyTest){
    # Update the value
    New-ItemProperty -Path $RegPath -Name $ValueName -Value $Value -PropertyType $ValueType -Force
    $Result="Key found: $valuename -Updated to 1"
}
else{
    # Add the registry key
    New-Item -Path $RegPath -Force
    # Create/update the value
    New-ItemProperty -Path $RegPath -Name $ValueName -Value $Value -PropertyType $ValueType -Force
    $Result="Key not found: $valuename -creating"
}

Exit 0
