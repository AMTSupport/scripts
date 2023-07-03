# Downlaod and run command line Speedtest
#John Noller - August 2020

Function Write-Log {
    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$True)]
    [string]
    $Message,

    [Parameter(Mandatory=$False)]
    [string]
    $logfile = "c:\temp\SpeedTest\SpeedTest.log"
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
$strPath = "c:\temp\SpeedTest"
$strPytonFileName = $strPath + "\python.exe"
$strPythonSource = "https://amt.com.au/downloads/speedtest/python.exe"
$strSpeedTestFileName = $strPath + "\speedtest.exe"
$strSpeedTestSource = "https://amt.com.au/downloads/speedtest/speedtest.exe"
$strSpeedtestOutputFileName = $strPath + "\SpeedtestOutput.txt"

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

#checik if python has already been download and if it has not download it
if (!(test-path $strPytonFileName))
{
    $WC = New-Object System.Net.WebClient
    Try
    {
        $WC.DownloadFile($strPythonSource, $strPytonFileName)
        Write-Log ("Python download succeeded")
    }
    Catch
    {
        Write-Log("Python download failed")
        Write-Host("Python download failed")
        Exit 1001
    }
}
else
{
     Write-Log ($strPytonFileName + " already existed")
}

#checik if speedtest has already been download and if it has not download it
if (!(test-path $strSpeedTestFileName))
{
    # try and downloa dthe speedtest propgram
    $WC = New-Object System.Net.WebClient
    Try
    {
        $WC.DownloadFile($strSpeedTestSource, $strSpeedTestFileName)
        Write-Log ("Speedtest download succeeded")
    }
    Catch
    {
        Write-Log("SpeedTest download failed")
        Write-Host("Speedtest download failed")
        Exit 1001
    }
}
else
{
     Write-Log ($strSpeedTestFileName + " already existed")
}

#try and run the speedtest program and if successful return the results.
try
{
    start-process -NoNewWindow -Wait -RedirectStandardOutput $strSpeedtestOutputFileName -filepath $strSpeedTestFileName  -ArgumentList "--accept-license"
    Write-Log("SpeedTest successfully  run")
    Write-Host "SpeedTest successfully  run"
    Get-Content $strSpeedtestOutputFileName
    exit 0

}
catch
{
    Write-Log("SpeedTest failed")
    Write-Host("SpeedTest  failed")
    Exit 1002
}
