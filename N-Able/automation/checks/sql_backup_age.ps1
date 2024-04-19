param($Location, $FileName)
Set-Location $Location
$Hours =  ((Get-Date)- (get-childitem $FileName).LastWriteTime).totalhours
$Hours = [math]::Round($Hours,2)
if ($Hours -lt 24)
    {write-host "Success: Last Backup " $Hours hours ago;
    exit 0}
else 
    {Write-Host "Failed: Last Backup" (get-childitem $FileName).LastWriteTime;
    Write-Host $Hours hours ago;
    exit 2001}

