#Installs Webroot using AMT license key.  See variable $strLicenseKey
#Phil Haddock - January 2017

Function Write-Log {
    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$True)]
    [string]
    $Message,

    [Parameter(Mandatory=$False)]
    [string]
    $logfile = "c:\temp\WebrootInstall.log"
    )

    $Stamp = (Get-Date).toString("yyyy-MM-dd HH:mm:ss")
    $Line = "$Stamp $Message"
    If($logfile) {
        Add-Content $logfile -Value $Line
    }
    Else {
        Write-Output $Line
    }
}

#Start deployment script

#First create target folder and file variables
$strPath = "c:\Temp"
$strFileName = $strPath + "\wsasme.msi"
$strLicenseKey = ""

#create folder if it doesn't exist
if (!(test-path $strpath))
{
new-item -type Directory -Force -Path $strPath
Write-Log ("Created " + $strPath)
}
else
{
Write-Log ($strPath + " already existed")
}

#remove file if it exists
if (Test-Path $strFileName)
{
Remove-item $strFileName
Write-Log ("Removed " + $strFileName)
}


#Download File
$Source = "http://anywhere.webrootcloudav.com/zerol/wsasme.msi"
$Destination = $strFileName
$WC = New-Object System.Net.WebClient
Try
{
    $WC.DownloadFile($Source, $Destination)
    Write-Log ("Installer download succeeded")
}
Catch
{
Write-Log("Installer download failed")
Write-Host("Installer download failed")
Exit 1001
}

#Install webroot
try
{
start-process -filepath msiexec -ArgumentList /i, $strFileName, "/qn", $strLicenseKey, "/l*v c:\temp\install.log" -wait
Write-Log("Webroot Installed")
}
catch
{
Write-Log("Webroot install failed")
Write-Host("Webroot install failed")
Exit 1002
}
#Check if Webroot installed
$Installed = Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object DisplayName|sort DisplayName|where {$_.displayname -like "Webroot*"}
if ($Installed.displayname.Length -gt 0)
{write-host "Webroot Installed"
Write-Log("Webroot Installed")
Exit 0
}
else
{
write-host "Check webroot installation log"
Write-Log("Webroot registry entry not detected.  It may not be installed correctly")
Exit 1003
}
