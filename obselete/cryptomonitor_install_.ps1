
(New-Object System.Net.WebClient).DownloadFile('http://www.amt.com.au/downloads/EasySync_CryptoMonitor_Setup.exe','C:\windows\temp\EasySync_CryptoMonitor_Setup.exe')

$MsiFileinBytes = 10056016
do {
  Start-Sleep -Seconds 2
  $FileSize = (Get-Item c:\windows\temp\EasySync_CryptoMonitor_Setup.exe).Length
} until ($FileSize -eq $MsiFileinBytes)
c:\windows\temp\EasySync_CryptoMonitor_Setup.exe /exenoui /qn
