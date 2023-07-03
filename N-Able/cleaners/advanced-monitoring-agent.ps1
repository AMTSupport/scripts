# '==================================================================================================================================================================
# 'Disclaimer
# 'The sample scripts are not supported under any SolarWinds support program or service.
# 'The sample scripts are provided AS IS without warranty of any kind.
# 'SolarWinds further disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose.
# 'The entire risk arising out of the use or performance of the sample scripts and documentation stays with you.
# 'In no event shall SolarWinds or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever
# '(including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss)
# 'arising out of the use of or inability to use the sample scripts or documentation.
# '==================================================================================================================================================================


Param(
    [string]$server = "system-monitor.com",
    [string]$apiKey,
    [string]$clientName,
    [string]$siteName,
    [string]$rebootForce = "Y",
    [int]$rebootCountdown = 10
)

function createTempItems() {
# Creates the log file, some instances the script failed due to ScriptCheckLog.txt not existing
    Write-Host "-----Running createTempItems() function-----"

    Write-Host "INFO: Attempting to create the script's log file and the C:\Temp\AgentInstall folder."

    try {
        New-Item -Path "C:\Temp\ScriptCheckLog.txt" -ItemType File -Force -ErrorAction Stop
    } catch {
        Write-Host "ERROR: Error creating the ScriptCheckLog.txt log file, due to:"
        Write-Host $_.Exception.Message
    }

    writeToLog "INFO: Started running script."

    try {
        New-Item -Path "C:\Temp\AgentInstall\" -ItemType Directory -Force -ErrorAction Stop
    } catch {
        writeToLog "ERROR: Error creating the AgentInstall folder."
        writeToLog $_.Exception
    }
    writeToLog "INFO: Log file and AgentInstall folder created successfully."
    writeToLog "INFO: Completed running createTempItems function."
    writeToLog "- - - - - - - - - - - - - - - -"
}
function validateUserInput() {
    writeToLog "INFO: Started running validateUserInput function."

# Ensures the provided input from user is valid
    If (($null -eq $server) -or ($server -eq "")) {
        writeToLog "FAILURE: No value has been given for the server variable."
        writeToLog "FAILURE: Please enter in your server address, for example: (UK - systemmonitor.co.uk.)"
        Exit 1001
    }
    If (($null -eq $apiKey) -or ($apiKey -eq "")) {
        writeToLog "FAILURE: No value has been given for the API Key."
        writeToLog "FAILURE: Please enter in your API Key which can be found under Settings > General Settings > API."
        Exit 1001
    }
    If (($null -eq $clientName) -or ($clientName -eq "")) {
        writeToLog "FAILURE: No Client name has been specified, please enter in the desired Client name."
        Exit 1001
    }
    If (($null -eq $siteName) -or ($siteName -eq "")) {
        writeToLog "FAILURE: No Site name has been specified, please enter in the desired Site name."
        Exit 1001
    }
    If (($null -eq $rebootForce) -or ($rebootForce -eq "")) {
        writeToLog "INFO: No forced reboot parameter has been specified, so reboot will not be forced."
        $script:rebootForce = "N"
    }
    If (($null -eq $rebootCountdown) -or ($rebootCountdown -eq "")) {
        writeToLog "INFO: No reboot time has been specified, so no reboot will be performed."
        $script:performReboot = "N"
    }

    writeToLog "INFO: Defined server address input set as:`r`n$server"
    writeToLog "INFO: Defined Client Name input set as:`r`n$clientName"
    writeToLog "INFO: Defined Site Name input set as:`r`n$siteName"

    writeToLog "INFO: Input Parameters have been successfully validated."
    writeToLog "INFO: Completed running validateUserInput function."
    writeToLog "- - - - - - - - - - - - - - - -"
}
function getOSName() {
    writeToLog "INFO: Started running getOSName function."

# Determines if device is XP/2003
# If so, then it is not compatible so exit script
    try {
        $wmiObjectOS = (Get-WMIObject win32_operatingsystem -ErrorAction Stop).name
        $script:wmiObjectName = (Get-WMIObject win32_computersystem -ErrorAction Stop).name
    }
    catch {
        writeToLog "ERROR: Unable to get Operating System information due to"
        writeToLog $_.Exception
    }

    If (($wmiObjectOS -like "*XP*") -or ($wmiObjectOS -like "*2003*")) {
        writeToLog "FAILURE: Device is not compatible as it's an XP/2003 device. Please perform migration manually."
        Exit 1001
    }

    $psVersion = $PSVersionTable.PSVersion

    writeToLog "INFO: Operating System of device detected as:`r`n$wmiObjectOS"
    writeToLog "INFO: Device is running the following version of Powershell:`r`n$psVersion"

    writeToLog "INFO: Device is suitable for migration, as it is not an XP/2003 device."
    writeToLog "INFO: Completed running getOSName function."
    writeToLog "- - - - - - - - - - - - - - - -"
}
function getAgentPath() {
    writeToLog "INFO: Started running getAgentPath function."
# If device is not XP/2003 (validated from the getOSName function), then get Advanced Monitoring Agent path from registry
    try {
        $Keys = Get-ChildItem HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall -ErrorAction Stop
    } catch {
        writeToLog "ERROR: Error occurred during the lookup of the CurrentVersion\Uninstall Path in the registry."
        writeToLog $_.Exception
    }

    $Items = $Keys | Foreach-Object {Get-ItemProperty $_.PsPath}

    ForEach ($Item in $Items) {
        If ($Item.DisplayName -like "Advanced Monitoring Agent" -or $Item.DisplayName -like "Advanced Monitoring Agent GP"){
            $script:localFolder = $Item.installLocation
            #$script:registryPath = $Item.PsPath
            #$script:registryName = $Item.PSChildName
            break
        }
    }

    try {
        $Keys = Get-ChildItem HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall -ErrorAction Stop
    } catch {
        writeToLog "ERROR: Error during the lookup of the WOW6432Node - CurrentVersion\Uninstall Path in the registry."
        writeToLog $_.Exception
    }

    $Items = $Keys | Foreach-Object {Get-ItemProperty $_.PsPath}

    ForEach ($Item in $Items) {
        If ($Item.DisplayName -like "Advanced Monitoring Agent" -or $Item.DisplayName -like "Advanced Monitoring Agent GP"){
            $script:localFolder = $Item.installLocation
            #$script:registryPath = $Item.PsPath
            #$script:registryName = $Item.PSChildName
            break
        }
    }

    If (!$script:localFolder) {
        writeToLog "FAILURE: Installation path for the Advanced Monitoring Agent location was not found."
		Exit 1001
    }

    If (($script:localFolder -match '.+?\\$') -eq $false) {
        $script:localFolder = $script:localFolder + "\"
    }

    #writeToLog "INFO: Determined registry path as:`r`n$registryPath"
    #writeToLog "INFO: Determined name as:`r`n$registryName"
    writeToLog "INFO: Agent install location:`r`n$script:localFolder"

    writeToLog "INFO: Completed running getAgentPath function."
    writeToLog "- - - - - - - - - - - - - - - -"
}
function clientSiteList() {
    writeToLog "INFO: Started running clientSiteList function."
# API call to list all clients and defines it as an xml

    $clientAPI = "https://$server/api/?apikey=$apiKey&service=list_clients"

    try {
        [xml]$script:xmlClient = (New-Object System.Net.WebClient).DownloadString($clientAPI)
    } catch [Net.WebException] {
        writeToLog "ERROR: Failed to retrieve Client data from API due to:"
        writeToLog $_.Exception.ToString()
    }

    $xmlClientStatus = $xmlClient.result.status

# Fail if the entered API key was invalid
    If ($xmlClientStatus -ne "OK") {
        $errorNumber = $xmlClient.result.error.errorcode
        $errorMessage = $xmlClient.result.error.message.InnerText
        writeToLog "FAILURE: Unable to retrieve data from API due to:"
        writeToLog "FAILURE: Error: $errorNumber, Details: $errorMessage"
        writeToLog "FAILURE: Please check the entered API key is correct and try again."
        Exit 1001
    }
    writeToLog "INFO: The 'list_clients' API call returned with the following status: $xmlClientStatus"

# For each of the clients in API call, get the Client information
    writeToLog "INFO: Successfully logged in with provided API key, will now build the Client information."

    $tempClientList = @()
    foreach ($client in $xmlClient.result.items.client) {
       $propertyList = [ordered]@{
            clientName = $client.name.InnerText
            clientID = $client.clientid
        }
        $objects = New-Object -TypeName pscustomobject -Property $propertyList
        $tempClientList += $objects
    }

# Takes all values from the $tempClientList variable and stores it in the $ClientArray variable and puts it to the parent scope
    Set-Variable -name clientArray -Value $tempClientList -scope global

# Now with the Client information stored under $clientArray, the following loops through to get the sites
    writeToLog "INFO: Client data now successfully retrieved. Will now get the Site information."

    $tempSiteList = @()
    foreach ($client in $clientArray) {
        $clientID = $client.clientid
        $siteAPI = "https://$server/api/?apikey=$apiKey&service=list_sites&clientid=$clientID"

        try {
            [xml]$script:xmlSite = (New-Object System.Net.WebClient).DownloadString($siteAPI)
        } catch [Net.WebException] {
            writeToLog "ERROR: Failed to retrieve Site data from API due to:"
            writeToLog $_.Exception.ToString()
        }

# For each of the sites in API call, get the sites information
        foreach ($site in $xmlSite.result.items.site) {
            $propertyList = [ordered]@{
                clientName = $client.clientname
                clientID = $clientID
                siteName = $site.name.InnerText
                siteID = $site.siteid
            }
            $objects= New-Object -TypeName pscustomobject -Property $propertyList
            $tempSiteList += $objects
        }
    }
    Set-Variable -name siteArray -Value $tempSiteList -scope global

    writeToLog "INFO: Client and Site data now successfully retrieved."
    writeToLog "INFO: Completed running clientSiteList function."
    writeToLog "- - - - - - - - - - - - - - - -"
}
function evaluateClientSite() {
    writeToLog "INFO: Started running evaluateClientSite function."

# From the user-defined Client/Site name, get ClientID and SiteID for API Installer
    $script:setClientID = (($siteArray | Where-Object {$_.clientName -eq $clientName}).clientID) | Sort-Object | Get-Unique
# Also included the clientID validation for instances where the site name is a duplicate across multiple clients
    $script:setSiteID = (($siteArray | Where-Object {$_.siteName -eq $siteName -and $_.clientName -eq $clientName}).siteID) | Sort-Object | Get-Unique

    If ($setClientID.count -gt 1) {
        writeToLog "FAILURE: With the given Client name, '$clientName', more than one Client has been determined."
        writeToLog "FAILURE: Please be more specific for the Client Name in the Command Line Parameters and re-run the script."
        Exit 1001
    }
    If ($setSiteID.count -gt 1) {
        writeToLog "FAILURE: With the given Site name, '$siteName', more than one Site has been determined."
        writeToLog "FAILURE: Please be more specific for the Site Name in the Command Line Parameters and re-run the script."
        Exit 1001
    }
    If ($setClientID.count -lt 1) {
        writeToLog "FAILURE: With the given Client name, '$clientName', no results have been determined."
        writeToLog "FAILURE: A total of 0 results found."
        Exit 1001
    }
    If ($setSiteID.count -lt 1) {
        writeToLog "FAILURE: With the given Site name, '$SiteName', no results have been determined."
        writeToLog "FAILURE: A total of 0 results found."
        Exit 1001
    }

    writeToLog "INFO: Evaluated ClientID as:`r`n$setClientID"
    writeToLog "INFO: Evaluated SiteID as:`r`n$setSiteID"

    writeToLog "INFO: Completed running evaluateClientSite function."
    writeToLog "- - - - - - - - - - - - - - - -"
}
function getSIPackage() {
    writeToLog "INFO: Started running getSIPackage function."

# Download the Site Installation Package from new location
    $global:siPackageAPI = "https://$server/api/?apikey=$apiKey&service=get_site_installation_package&endcustomerid=$setClientID&siteid=$setSiteID&type=remote_worker"

    $script:downloadLocation = "C:\Temp\AgentInstall\"
    $script:localFile = "packageinstaller.zip"

    $source = $siPackageAPI
    $dest = $downloadLocation+$localFile

    writeToLog "INFO: Downloading the Advanced Monitoring Agent installer."
    writeToLog "INFO: This is being directed to the following location:`r`n$dest"

    $wc = New-Object System.Net.WebClient

    try {
        $wc.DownloadFile($source, $dest)
    }
    catch [System.Net.WebException] {
        writeToLog "FAILURE: The Agent installer failed to download, due to:"

        If ($_.Exception.InnerException) {
            $innerException = $_.Exception.InnerException.Message
            writeToLog $innerException
            Exit 1001
        } Else {
            $exception = $_.Exception.Message
            writeToLog $exception
            Exit 1001
        }
    }

    writeToLog "INFO: The Advanced Monitoring Agent Remote Worker installer has now downloaded successfully."
    writeToLog "INFO: Completed running getSIPackage function."
    writeToLog "- - - - - - - - - - - - - - - -"
}
function unzipSIContents() {
    writeToLog "INFO: Started running unzipSIContents function."

# Extract the contents of the downloaded SI package
    $script:extractLocation = "C:\Temp\AgentInstall\Package\"
    New-Item -Path $extractLocation -ItemType directory -Force | out-null
    $localFile = "packageinstaller.zip"

    writeToLog "INFO: Source file:`r`n$downloadLocation$localFile"
    writeToLog "INFO: Extract location:`r`n$extractLocation"
    writeToLog "INFO: ExExtracting zip for the Remote Worker installer."

    Expand-Archive $downloadLocation$localFile $extractLocation -Force

    $extractTest = Test-Path $extractLocation

    writeToLog "INFO: Extract location detection returned as:`r`n$extractTest"

    If ($extractTest -ne $true) {
        writeToLog "FAILURE: Failing script, extract location does not exist."
        Exit 1001
    }

    $extractFile = (Get-ChildItem $extractLocation).FullName

    writeToLog "INFO: Remote Worker extracted successfully, known as:`r`n$extractFile"
    writeToLog "INFO: Completed running unzipSIContents function."
    writeToLog "- - - - - - - - - - - - - - - -"
}
function createActionTool() {
    writeToLog "INFO: Started running createActionTool function."
    writeToLog "INFO: Currently creating the ActionTool.ps1 script, storing within the C:\Temp\AgentInstall\ location."

    $runOnceKey = "Run"
    $actionCommand = "%systemroot%\System32\WindowsPowerShell\v1.0\powershell.exe -executionpolicy bypass -file C:\Temp\AgentInstall\ActionTool.ps1"

    New-Item -Path "C:\Temp\AgentInstall\ActionTool.ps1" -ItemType file -Force

    $scriptContent = '
    function runInstaller() {
        writeToLog "INFO: Started running runInstaller function."

        $extractedfile = get-childitem $extractLocation -filter *.exe

        $switches = "/S"

        writeToLog "INFO: Now performing installation of the new Advanced Monitoring Agent."

        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $extractLocation+$extractedfile
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.UseShellExecute = $false
        $pinfo.Arguments = $switches
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
        $p.WaitForExit()
        $script:ExitCode = $p.ExitCode

        writeToLog "INFO: The Exit Code is:`r`n$ExitCode"
    #    writeToLog "INFO: Now going to remove the files and folders from the temporary directory."

    #    Remove-Item "C:\Temp\AgentInstall\" -Recurse -Force

        writeToLog "INFO: Completed running runInstaller function"
        writeToLog "- - - - - - - - - - - - - - - -"
    }
    function Get-TimeStamp() {
        return "[{0:dd/MM/yyyy} {0:HH:mm:ss}]" -f (Get-Date)
    }
    function writeToLog($message) {
        $logFile = "C:\Temp\ScriptCheckLog.txt"
        Write-Host $message
        Write-Output "$(Get-TimeStamp): $message" | Out-file $logFile -Append
    }
    function main() {
    # Main function, set to run other functions
        runInstaller

        writeToLog "INFO: Installation of the Remote Worker has now completed."
        writeToLog "INFO: Device should now be checking into the new Dashboard under the location shown above."
    }
    main
    '
    Add-Content "C:\Temp\AgentInstall\ActionTool.ps1" $scriptContent -Encoding UTF8

    writeToLog "INFO: ActionTool.ps1 now created. Will now place in RunOnce."

    If (-not ((Get-Item -Path HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce).$runOnceKey)) {
        New-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name $runOnceKey -Value $actionCommand -PropertyType ExpandString
    } Else {
        Set-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name $runOnceKey -Value $actionCommand -PropertyType ExpandString
    }

    writeToLog "INFO: Registry updated with RunOnce parameter."
    writeToLog "INFO: Completed running createActionTool function."
    writeToLog "- - - - - - - - - - - - - - - -"
}
function stopAgentServices() {
    writeToLog "INFO: Started running stopAgentServices function."

    writeToLog "INFO: Will attempt to stop the services, to assist with the uninstall process."

    $amaServiceName = "Advanced Monitoring Agent"
    $amaWPServiceName = "Advanced Monitoring Agent Web Protection"
    $amaNMServiceName = "Advanced Monitoring Agent Network Management"

    try {
        $script:amaService = Get-Service $amaServiceName -ErrorAction Stop
    } catch {
        writeToLog "ERROR: Error determining the Advanced Monitoring Agent service:"
        writeToLog $_.Exception
    }

    try {
        Stop-Service $amaService -ErrorAction Stop
    } catch {
        writeToLog "ERROR: Error attempting to stop the Advanced Monitoring Agent service:"
        writeToLog $_.Exception
    }

    writeToLog "INFO: Successfully stopped the Advanced Monitoring Agent service, will now try to stop any auxiliary Advanced Monitoring Agent services if they exist."

    If (Get-Service $amaWPServiceName -ErrorAction SilentlyContinue) {
        If ((Get-Service $amaWPServiceName).Status -eq "Running") {
            writeToLog "INFO: Found the $amaWPServiceName service running, will now attempt to stop."
            try {
                Stop-Service $amaWPServiceName -ErrorAction Stop
            } catch {
                writeToLog "ERROR: Error attempting to stop the $amaWPServiceName service:"
                writeToLog $_.Exception
            }
        }
    }
    If (Get-Service $amaNMServiceName -ErrorAction SilentlyContinue) {
        If ((Get-Service $amaNMServiceName).Status -eq "Running") {
            writeToLog "INFO: Found the $amaNMServiceName service running, will now attempt to stop."
            try {
                Stop-Service $amaNMServiceName -ErrorAction Stop
            } catch {
                writeToLog "ERROR: Error attempting to stop the $amaNMServiceName service:"
                writeToLog $_.Exception
            }
        }
    }

    writeToLog "INFO: Completed running stopAgentServices function."
    writeToLog "- - - - - - - - - - - - - - - -"
}
function moveUninstaller() {
    writeToLog "INFO: Started running moveUninstaller function."

    writeToLog "INFO: Testing location of the uninstaller."

# Now the SI package is downloaded, continue on with uninstalling original Advanced Monitoring Agent.
    $uninstaller = $localFolder + "unins000.exe"
    $uninsCheck = Test-Path $uninstaller

    writeToLog "INFO: Determined uninstaller as:`r`n$uninstaller"
    writeToLog "INFO: Determined uninstaller as:`r`n$uninsCheck"

    If ($uninsCheck -eq $false) {
        writeToLog "FAILURE: Failed to locate the uninstaller."
        Exit 1001
    }

# Copying both unins000.exe and unins000.dat to temp folder, due to issues with .dat being in use with another process
    try {
        Copy-Item ($localfolder + "unins*") "C:\Temp\AgentInstall\" -Force -ErrorAction Stop
    } catch {
        writeToLog "FAILURE: Error copying uninstaller to temporary location:"
        writeToLog $_.Exception
        writeToLog "FAILURE: Will fail script since the uninstall cannot be performed."
        Exit 1001
    }

    $script:uninsExePath = "C:\Temp\AgentInstall\unins000.exe"
    $script:uninsDatPath = "C:\Temp\AgentInstall\unins000.dat"
    $uninsCheckExe = Test-Path $uninsExePath
    $uninsCheckDat = Test-Path $uninsDatPath

    If (($uninsCheckExe -eq $false) -or ($uninsCheckDat -eq $false)) {
        writeToLog "FAILURE: Failed to copy uninstaller to the temporary location."
        Exit 1001
    }

# If _iu14D2N.tmp is present on the device, the uninstall will not be able to occur
    try {
        $uninsLockProcTest = Get-Process -ProcessName "_iu*" -ErrorAction Stop
    } catch {
        writeToLog "ERROR: Error detecting uninstaller lock file, due to:"
        writeToLog $_.Exception
    }

    $uninsLockPathTest = Test-Path "$Env:USERPROFILE\AppData\Local\Temp\_iu*"

    If ((($uninsLockProcTest.ProcessName -like "_iu*") -eq $true) -or ($uninsLockPathTest -eq $true)) {
        writeToLog "FAILURE: Detected _iu14D2N.tmp on the device, which is locking the uninstall of the Advanced Monitoring Agent."
        writeToLog "FAILURE: Due to this, it is not possible to complete the uninstall of the Advanced Monitoring Agent."
        writeToLog "FAILURE: Please reboot the device and try running the script again."
        Exit 1001
    }

    writeToLog "INFO: Completed running moveUninstaller function."
    writeToLog "- - - - - - - - - - - - - - - -"
}
function performUninstall() {
    writeToLog "INFO: Started running performUninstall function."

    $switches = "/SILENT"

    writeToLog "INFO: Now running the Advanced Monitoring Agent uninstaller."
    writeToLog "INFO: Invoking the uninstaller from the following location:`r`n$uninsExePath"

    Start-Process $uninsExePath $switches -Wait

    writeToLog "INFO: Completed running performUninstall function."
    writeToLog "- - - - - - - - - - - - - - - -"
}
function performReboot() {
    writeToLog "INFO: Started running performReboot function."

# Will now check if reboot has been allowed, and if so it is is allowed to be a forced reboot.
    If (($null -eq $rebootCountdown) -or ($rebootCountdown -eq "")) {
        writeToLog "INFO: No reboot value has been defined, so no reboot will be performed."
        writeToLog "INFO: Due to this, device will not complete the migration until such time this is performed."
    } Else {
        writeToLog "INFO: Reboot set to occur in $rebootCountdown seconds."
        If ($rebootForce -eq "Y") {
            writeToLog "INFO: A forced reboot has been allowed to perform."

            cmd.exe /c "shutdown /r /f /t $rebootCountdown"
        } Else {
            writeToLog "INFO: A forced reboot has not been allowed to perform."

            cmd.exe /c "shutdown /r /t $rebootCountdown"
        }
    }

    writeToLog "INFO: Completed running performReboot function."
    writeToLog "- - - - - - - - - - - - - - - -"
}
function Get-TimeStamp() {
    return "[{0:dd/MM/yyyy} {0:HH:mm:ss}]" -f (Get-Date)
}
function writeToLog($message) {
    $logFile = "C:\Temp\ScriptCheckLog.txt"
    Write-Host $message
    Write-Output "$(Get-TimeStamp): $message" | Out-file $logFile -Append
}
function main() {
# Main function, set to run other functions
    createTempItems
    validateUserInput
    getOSName
    getAgentPath
    ClientSiteList
    evaluateClientSite
    #getSIPackage
    #unzipSIContents
    #createActionTool
    #stopAgentServices
    #moveUninstaller
    #performUninstall
    #performReboot

    writeToLog "INFO: Initial phase of migration has been completed."
    writeToLog "INFO: Device will be migrated to:`r`nClientName: $clientName`r`nSiteName: $siteName`r`nDeviceName: $wmiObjectName"
}
main
