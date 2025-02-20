#!ignore "6d8c860193b8dd929f999d0fb4ee7040"
# '==================================================================================================================================================================
# 'Disclaimer
# 'The sample scripts are not supported under any N-able support program or service.
# 'The sample scripts are provided AS IS without warranty of any kind.
# 'N-able further disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose.
# 'The entire risk arising out of the use or performance of the sample scripts and documentation stays with you.
# 'In no event shall N-able or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever
# '(including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss)
# 'arising out of the use of or inability to use the sample scripts or documentation.
# '==================================================================================================================================================================

Param (
    [string]$verbose = "Y"
)

function setupLogging() {
    $script:logFilePath = $env:ProgramData + "\MspPlatform\Tech Tribes\N-sight RMM Cleanup\debug.log"

	$script:logFolder = Split-Path $logFilePath
	$script:logFile = Split-Path $logFilePath -Leaf

    If (($logFolder -match '.+?\\$') -eq $false) {
        $script:logFolder = $script:logFolder + "\"
    }

    $logFolderExists = Test-Path $logFolder
    $logFileExists = Test-Path $logFilePath

    If ($logFolderExists -eq $false) {
        New-Item -ItemType "directory" -Path $logFolder | Out-Null
    }

    If ($logFileExists -eq $true) {
		Remove-Item $logFilePath -ErrorAction SilentlyContinue
		Start-Sleep 2
		New-Item -ItemType "file" -Path $logFolder -Name $logFile | Out-Null
    } Else {
		New-Item -ItemType "file" -Path $logFolder -Name $logFile | Out-Null
    }

    [float]$script:currentVersion = 1.05
    writeToLog I "Started processing the N-sightRMMCleanup script."
    writeToLog I "Running script version: $currentVersion"
}

function validateUserInput() {
    If ($verbose.ToLower() -eq "y") {
        $script:verboseMode = $true
        writeToLog V "You have defined to have the script output the verbose log entries."
    } Else {
        $script:verboseMode = $false
        writeToLog I "Will output logs in regular mode."
    }

    writeToLog V "Input Parameters have been successfully validated."
    writeToLog V ("### Completed running {0} function. ###`r`n" -f $MyInvocation.MyCommand)
}

function getAgentPath() {
	writeToLog V ("### Started running {0} function. ###" -f $MyInvocation.MyCommand)

    If ($currentPSVersion -lt [version]5.1) {
        writeToLog W "Device is currently using this powershell version so may fail due to compatibility issues:`r`n`t$currentPSVersion"
        $script:legacyPS = $true
    } Else {
        writeToLog V "Confirmed device is using supported Powershell version:`r`n`t$currentPSVersion"
        $script:legacyPS = $false
    }

    try {
        $Keys = Get-ChildItem HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall -ErrorAction Stop
    } catch {
        $msg = $_.Exception.Message
        $line = $_.InvocationInfo.ScriptLineNumber
        writeToLog W "Error occurred during the lookup of the CurrentVersion\Uninstall Path in the registry, due to:`r`n`t$msg"
        writeToLog V "This occurred on line number: $line"
        writeToLog W "Will continue with validating agent path."
    }

    $Items = $Keys | Foreach-Object {
        Get-ItemProperty $_.PsPath
    }

    ForEach ($Item in $Items) {
        If ($Item.DisplayName -like "Advanced Monitoring Agent" -or $Item.DisplayName -like "Advanced Monitoring Agent GP"){
            $script:localFolder = $Item.installLocation
            $script:registryPath = $Item.PsPath
            $registryName = $Item.PSChildName
            $registryDisplayName = $Item.DisplayName
            $registryVersion = $Item.DisplayVersion
            $registryInstallDate = $Item.InstallDate
            break
        }
    }

    try {
        $Keys = Get-ChildItem HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall -ErrorAction Stop
    } catch {
        $msg = $_.Exception.Message
        $line = $_.InvocationInfo.ScriptLineNumber
        writeToLog W "Error occurred during the lookup of the CurrentVersion\Uninstall Path in the registry, due to:`r`n`t$msg"
        writeToLog V "This occurred on line number: $line"
        writeToLog W "Will continue with validating agent path."
    }

    $Items = $Keys | Foreach-Object {
        Get-ItemProperty $_.PsPath
    }

    ForEach ($Item in $Items) {
        If ($Item.DisplayName -like "Advanced Monitoring Agent" -or $Item.DisplayName -like "Advanced Monitoring Agent GP"){
            $script:localFolder = $Item.installLocation
            $script:registryPath = $Item.PsPath
            $registryName = $Item.PSChildName
            $registryDisplayName = $Item.DisplayName
            $registryVersion = $Item.DisplayVersion
            $registryInstallDate = $Item.InstallDate
            break
        }
    }
    
    If (!$script:localFolder) {
        writeToLog F "Installation path for the Advanced Monitoring Agent location was not found."
        writeToLog F "Failing script."
        Exit 1001
    }

    If (($script:localFolder -match '.+?\\$') -eq $false) {
        $script:localFolder = $script:localFolder + "\"
    }

    writeToLog V "Determined registry path as:`r`n`t$registryPath"
    writeToLog V "Determined key name as:`r`n`t$registryName"
    writeToLog V "Determined DisplayName as:`r`n`t$registryDisplayName"
    writeToLog V "Determined version as:`r`n`t$registryVersion"
    writeToLog V "Determined installed date as:`r`n`t$registryInstallDate"

    writeToLog V "Detected Advanced Monitoring Agent install location:`r`n`t$localFolder"

    If (!(Test-Path ("$localFolder" + "unins000.exe"))) {
        writeToLog W "The uninstaller is not present (likely GP deployment)."
        writetoLog W "Downloading uninstaller."
        downloadUnins
    } Else {
        writeToLog I "The unins000.exe is present."
    }

    writeToLog V ("### Completed running {0} function. ###`r`n" -f $MyInvocation.MyCommand)
}

function moveUninstaller() {
    writeToLog V ("### Started running {0} function. ###" -f $MyInvocation.MyCommand)

    # If '_iu14D2N.tmp' is present on the device, then we will try to kill it
    try {
        $uninsLockProcTest = Get-Process -ProcessName "_iu*" -ErrorAction Stop
    } catch {
        writeToLog W "Error detecting uninstaller lock file, due to:"
        writeToLog W $_
    }

    If ($null -ne $uninsLockProcTest) {
        writeToLog I "Detected $uninsLockProcTest on the device, removing."
        try {
            Stop-Process $uninsLockProcTest -Force -ErrorAction Stop
        } catch {
            writeToLog W "Error stopping uninstall lock process:"
            writeToLog W $_
        }
    }

    $uninsLockPath = "$Env:USERPROFILE\AppData\Local\Temp\_iu*"
    $uninsLockPathTest = Test-Path $uninsLockPath

    If ($uninsLockPathTest -eq $true) {
        writeToLog W "Detected $uninsLockPath on the device, removing."
        Remove-Item "$Env:USERPROFILE\AppData\Local\Temp\_iu*" -Force
    }

    $newUninsExePath = $logFolder + "unins000.exe"
    $newUninsDatPath = $logFolder + "unins000.dat"

    $newUninsExeTest = Test-Path $newUninsExePath
    $newUninsDatTest = Test-Path $newUninsDatPath

    If ($newUninsExeTest -eq $true) {
        writeToLog W "Previous unins000.exe found in the log folder, will forcibly remove."

        try {
            Remove-Item $newUninsExePath -Force -Recurse -ErrorAction Stop
        }
        catch {
            $msg = $_.Exception.Message
            $line = $_.InvocationInfo.ScriptLineNumber
            writeToLog F "Error occurred when removing old unins000.exe from device, due to:`r`n`t$msg"
            writeToLog V "This occurred on line number: $line"
            writeToLog F "Failing script."
            Exit 1001
        }
    }
    If ($newUninsDatTest -eq $true) {
        writeToLog W "Previous unins000.dat found in the log folder, will forcibly remove."

        try {
            Remove-Item $newUninsDatPath -Force -Recurse -ErrorAction Stop
        }
        catch {
            $msg = $_.Exception.Message
            $line = $_.InvocationInfo.ScriptLineNumber
            writeToLog F "Error occurred when removing old unins000.dat from device, due to:`r`n`t$msg"
            writeToLog V "This occurred on line number: $line"
            writeToLog F "Failing script."
            Exit 1001
        }
    }

    writeToLog V "Testing location of the uninstaller."

# Now the SI package is downloaded, continue on with uninstalling original Advanced Monitoring Agent.
    $uninstaller = $localFolder + "unins000.exe"
    $uninsCheck = Test-Path $uninstaller

    writeToLog V "Determined uninstaller location as:`r`n`t$uninstaller"
    writeToLog V "Uninstaller detected returned as:`r`n`t$uninsCheck"

    If ($uninsCheck -eq $false) {
        writeToLog W "Failed to locate the uninstaller in the Advanced Monitoring Agent installation directory."
        writeToLog W "Will attempt to download instead."
        downloadUnins
    } Else {
        # Copying both unins000.exe and unins000.dat to temp folder, due to issues with .dat being in use with another process
        try {
            Copy-Item ($localFolder + "unins*") $logFolder -Force -ErrorAction Stop
        } catch {
            $msg = $_.Exception.Message
            $line = $_.InvocationInfo.ScriptLineNumber
            writeToLog F "Error occurred when copying uninstaller over to temporary location, due to:`r`n`t$msg"
            writeToLog V "This occurred on line number: $line"
            writeToLog F "Due to this, uninstall cannot be performed."
            writeToLog F "Failing script."
            Exit 1001
        }

        writeToLog V "Uninstaller now moved to the following location:`r`n`t$logFolder"
    }

    $script:uninsExePath = $logFolder + "unins000.exe"
    $script:uninsDatPath = $logFolder + "unins000.dat"

    $uninsCheckExe = Test-Path $uninsExePath
    $uninsCheckDat = Test-Path $uninsDatPath

    If (($uninsCheckExe -eq $false) -or ($uninsCheckDat -eq $false)) {
        writeToLog F "Failed to copy uninstaller to the temporary location."
        writeToLog F "Failing script."
        Exit 1001
    }

    writeToLog V "Uninstaller exe detection for new location returned as:`r`n`t$uninsCheckExe"
    writeToLog V "Uninstaller dat detection for new location returned as:`r`n`t$uninsCheckDat"

# If '_iu14D2N.tmp' is present on the device, the uninstall will not be able to occur
    try {
        $uninsLockProcTest = Get-Process -ProcessName "_iu*" -ErrorAction Stop
    } catch {
        $msg = $_.Exception.Message
        $line = $_.InvocationInfo.ScriptLineNumber
        writeToLog W "Error detecting uninstaller lock file, due to:`r`n`t$msg"
        writeToLog V "This occurred on line number: $line"
    }

    $uninsLockPathTest = Test-Path "$Env:USERPROFILE\AppData\Local\Temp\_iu*"

    If ((($uninsLockProcTest.ProcessName -like "_iu*") -eq $true) -or ($uninsLockPathTest -eq $true)) {
        writeToLog F "Detected _iu14D2N.tmp on the device, which is locking the uninstall of the Advanced Monitoring Agent."
        writeToLog F "Due to this, it is not possible to complete the uninstall of the Advanced Monitoring Agent."
        writeToLog F "Please reboot the device and try running the script again."
        writeToLog F "Failing script."
        Exit 1001
    }

    writeToLog V "Uninstall lock not detected on the device, nor found as a running process/existing file."

    writeToLog V ("### Completed running {0} function. ###`r`n" -f $MyInvocation.MyCommand)
}

function downloadUnins() {
    writeToLog V ("### Started running {0} function. ###" -f $MyInvocation.MyCommand)

    $uninsURL = "https://s3.amazonaws.com/new-swmsp-net-supportfiles/PermanentFiles/AMARemoval/unins000.zip"

    $script:downloadLocation = $logFolder
    $script:localFile = "unins000.zip"

    $source = $uninsURL
    $dest = $downloadLocation+$localFile

    writeToLog I "Downloading the Advanced Monitoring Agent uninstaller."
    writeToLog V "This is being directed to the following location:`r`n`t$dest"

    $oldZipPresent = Test-Path $dest

    If ($oldZipPresent -eq $true) {
        writeToLog V "Previous unins000.zip present on device, removing."
        Remove-Item $dest -Force | Out-Null
    }

    $wc = New-Object System.Net.WebClient

    try {
        $wc.DownloadFile($source, $dest)
    }
    catch [System.Net.WebException] {
        writeToLog F "The Agent uninstaller zip file failed to download, due to:"

        If ($_.Exception.InnerException) {
            $innerException = $_.Exception.InnerException.Message
            writeToLog F $innerException
            writeToLog F "Failing script."
            Exit 1001
        } Else {
            $exception = $_.Exception.Message
            writeToLog F $exception
            writeToLog F "Failing script."
            Exit 1001
        }
    }

    $script:extractLocation = $logFolder

    writeToLog I "Extracting zip for the Advanced Monitoring Agent uninstaller."

    $downloadedFile = $dest

    try {
        If ($legacyPS -eq $false) {
            Expand-Archive $downloadedFile $logFolder -ErrorAction Stop
        } Else {
            $filePath = $downloadedFile
            $script:shell = New-Object -ComObject Shell.Application
            $zipFile = $shell.NameSpace($filePath)
            $destinationFolder = $shell.NameSpace($logFolder)

            $copyFlags = 0x00
            $copyFlags += 0x04
            $copyFlags += 0x10

            $destinationFolder.CopyHere($zipFile.Items(), $copyFlags)
        }
    } catch {
        $msg = $_.Exception.Message
        $line = $_.InvocationInfo.ScriptLineNumber
        writeToLog E "Error occurred when extracting the Advanced Monitoring Agent uninstaller, due to:`r`n`t$msg"
        writeToLog V "This occurred on line number: $line"
        writeToLog F "Failing script."
    }
    <#
    If ($missingCmdlet -eq $true) {
        writeToLog W "Expand-Archive not an applicable cmdlet, due to an old version of Powershell."
        writeToLog V "Will attempt extracting the uninstaller files using the Shell.Application object."

        $script:shell = new-object -com Shell.Application
        $shell.namespace($logFolder).copyhere($shell.namespace($downloadedFile).items(),16)
    
    } Else {
        try {
            Expand-Archive $downloadedFile $logFolder -Force -ErrorAction Stop
        }
        catch {
            $msg = $_.Exception.Message
            $line = $_.InvocationInfo.ScriptLineNumber
            writeToLog W "Error occurred when extracting the Advanced Monitoring Agent uninstaller from the zip file, due to:`r`n`t$msg"
            writeToLog V "This occurred on line number: $line"
            writeToLog F "Failing script."
            Exit 1001
        }
    }
    #>

    $uninstallerPath = $logFolder + "unins000.exe"
    $extractTest = Test-Path $uninstallerPath

    writeToLog V "Testing path:`r`n`t$uninstallerPath"
    writeToLog V "Extract location detection returned as:`r`n`t$extractTest"

    If ($extractTest -ne $true) {
        writeToLog F "An issue occurred when trying to extract the Advanced Monitoring Agent uninstaller to the following location:`r`n`t$uninstallerPath"
        writeToLog F "Failing script."
        Exit 1001
    }

    $extractFile = (Get-ChildItem $extractLocation).FullName

    writeToLog I "Advanced Monitoring Agent uninstaller extracted successfully, which is extracted to:`r`n`t$extractFile"

    writeToLog V ("### Completed running {0} function. ###`r`n" -f $MyInvocation.MyCommand)
}

function stopAgentServices() {
    writeToLog V ("### Started running {0} function. ###" -f $MyInvocation.MyCommand)

    writeToLog I "Attempting to stop the Advanced Monitoring Agent services, to assist with the uninstall process."

    $script:amaServiceName = "Advanced Monitoring Agent"
    $script:amaWPServiceName = "Advanced Monitoring Agent Web Protection"
    $script:amaNMServiceName = "Advanced Monitoring Agent Network Management"

    try {
        $script:amaService = Get-Service $amaServiceName -ErrorAction Stop -WarningAction SilentlyContinue
    } catch {
        $msg = $_.Exception.Message
        $line = $_.InvocationInfo.ScriptLineNumber
        writeToLog W "Error occurred when detecting the Advanced Monitoring Agent service, due to:`r`n`t$msg"
        writeToLog V "This occurred on line number: $line"
    }

    try {
        Stop-Service $amaService -Force -ErrorAction Stop  -WarningAction SilentlyContinue | Out-Null
    } catch {
        $msg = $_.Exception.Message
        $line = $_.InvocationInfo.ScriptLineNumber
        writeToLog W "Error occurred when stopping the Advanced Monitoring Agent service, due to:`r`n`t$msg"
        writeToLog V "This occurred on line number: $line"
    }

    Start-Sleep 5

    try {
        $script:amaService = Get-Service $amaServiceName -ErrorAction Stop -WarningAction SilentlyContinue
    } catch {
        $msg = $_.Exception.Message
        $line = $_.InvocationInfo.ScriptLineNumber
        writeToLog W "Error occurred when detecting the Advanced Monitoring Agent service, due to:`r`n`t$msg"
        writeToLog V "This occurred on line number: $line"
    }

    writeToLog I "Advanced Monitoring Agent Windows Service Status: $($amaService.Status)"

    writeToLog I "Removing the Advanced Monitoring Agent service."

    try {
        $script:amaService = sc.exe delete $amaServiceName -ErrorAction Stop -WarningAction SilentlyContinue
    } catch {
        $msg = $_.Exception.Message
        $line = $_.InvocationInfo.ScriptLineNumber
        writeToLog W "Error occurred when removing the Advanced Monitoring Agent service, due to:`r`n`t$msg"
        writeToLog V "This occurred on line number: $line"
    }

    writeToLog I "Moving onto auxiliary Advanced Monitoring Agent services."

    If (Get-Service $amaWPServiceName -ErrorAction SilentlyContinue) {
        If ((Get-Service $amaWPServiceName).Status -eq "Running") {
            writeToLog V "Found the $amaWPServiceName service running, will now attempt to stop."
            try {
                Stop-Service $amaWPServiceName -Force -ErrorAction Stop  -WarningAction SilentlyContinue | Out-Null
            } catch {
                $msg = $_.Exception.Message
                $line = $_.InvocationInfo.ScriptLineNumber
                writeToLog W "Error occurred when stopping the $amaWPServiceName service, due to:`r`n`t$msg"
                writeToLog V "This occurred on line number: $line"
            }
        }
    }
    If (Get-Service $amaNMServiceName -ErrorAction SilentlyContinue) {
        If ((Get-Service $amaNMServiceName).Status -eq "Running") {
            writeToLog V "Found the $amaNMServiceName service running, will now attempt to stop."
            try {
                Stop-Service $amaNMServiceName -Force -ErrorAction Stop  -WarningAction SilentlyContinue | Out-Null
            } catch {
                $msg = $_.Exception.Message
                $line = $_.InvocationInfo.ScriptLineNumber
                writeToLog W "Error occurred when stopping the $amaNMServiceName service, due to:`r`n`t$msg"
                writeToLog V "This occurred on line number: $line"
            }
        }
    }

    writeToLog V ("### Completed running {0} function. ###`r`n" -f $MyInvocation.MyCommand)
}

function performUninstall() {
	writeToLog V ("### Started running {0} function. ###" -f $MyInvocation.MyCommand)

    $uninsExePath = $localFolder + "unins000.exe"
    $uninsDatPath = $localFolder + "unins000.dat"

    writeToLog I "Now running the Advanced Monitoring Agent uninstaller."
    writeToLog I "Invoking the uninstaller from the following location:`r`n`t$uninsExePath"

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $uninsExePath
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = "/SILENT"

    $installArgs = $pinfo.Arguments
    writeToLog V "Uninstall Arguments set: $installArgs"

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $p.WaitForExit()
    $script:exitCode = $p.ExitCode

    If ($exitCode -ne 0) {
        writeToLog W "Did not successfully perform uninstall, as Exit Code is: $exitCode"
    } Else {
        writeToLog I "Successfully performed uninstall, as the returned Exit Code is: $exitCode"
    }

    Start-Sleep 10

    writeToLog V ("### Completed running {0} function. ###`r`n" -f $MyInvocation.MyCommand)
}

function postUninstall() {
    writeToLog V ("### Started running {0} function. ###" -f $MyInvocation.MyCommand)

    # Confirm pid is removed
    try {
        $winagentProcess = Get-Process -Name "winagent" -ErrorAction SilentlyContinue | Select-Object Name,ProcessName,Id
    } catch {
        $msg = $_.Exception.Message
        $line = $_.InvocationInfo.ScriptLineNumber
        writeToLog W "Error occurred when stopping the $amaNMServiceName service, due to:`r`n`t$msg"
        writeToLog V "This occurred on line number: $line"
    }

    If ($winagentProcess) {
        writeToLog W "Winagent process detected:`r`n`tName: $($winagentProcess.Name)`r`n`tFullName: $($winagentProcess.ProcessName)`r`n`tProcessID: $($winagentProcess.Id)"
        writeToLog W "Winagent process is still running on the device, attempting to terminate process."

        try {
            $winagentProcess | Stop-Process -Force -ErrorAction Stop
        } catch {
            $msg = $_.Exception.Message
            $line = $_.InvocationInfo.ScriptLineNumber
            writeToLog W "Error occurred when terminating the 'winagent' process, due to:`r`n`t$msg"
            writeToLog V "This occurred on line number: $line"
        }
    } Else {
        writeToLog V "Confirmed the Advanced Monitoring Agent process (winagent) is no longer present."
    }

    # Confirm service is removed
    try {
        $script:amaService = Get-Service $amaServiceName -ErrorAction SilentlyContinue
    } catch {
    }

    If ($null -eq $amaService) {
        writeToLog V "Confirmed the Advanced Monitoring Agent Windows Service no longer exists."
    } Else {
        writeToLog W "The Advanced Monitoring Agent service still exists on the device."
    }

    writeToLog V ("### Completed running {0} function. ###" -f $MyInvocation.MyCommand)
}

function cleanupAgentData() {
    writeToLog V ("### Started running {0} function. ###" -f $MyInvocation.MyCommand)

    $winagentPath = $localFolder + "winagent.exe"
    $agentSettingsPath = $localFolder + "settings.ini"

    $winagentExists = Test-Path $winagentPath
    $agentSettingsExists = Test-Path $agentSettingsPath

    If ($agentSettingsExists -eq $true) {
        writeToLog W "Settings.ini still exists on the device, forcibly removing file."

        try {
            Remove-Item $agentSettingsPath -Force -ErrorAction Stop
        }
        catch {
            $msg = $_.Exception.Message
            $line = $_.InvocationInfo.ScriptLineNumber
            writeToLog W "Unable to remove settings.ini from device, due to:`r`n`t$msg"
            writeToLog V "This occurred on line number: $line"
        }
    } Else {
        writeToLog V "Confirmed settings.ini no longer exists on the device."
    }

    If ($winagentExists -eq $true) {
        writeToLog F "The Advanced Monitoring Agent is still installed."
        writeToLog F "Failing script."
        Exit 1001
    } Else {
        writeToLog I "The Advanced Monitoring Agent's Winagent.exe application no longer exists, so removal has been successful."
        writeToLog V "Cleaning up the Advanced Monitoring Agent install location."

        try {
            Remove-Item $localFolder -Force -Recurse -ErrorAction Stop
        }
        catch {
            $msg = $_.Exception.Message
            $line = $_.InvocationInfo.ScriptLineNumber
            writeToLog W "Unable to remove Advanced Monitoring Agent folder from device, due to:`r`n`t$msg"
            writeToLog V "This occurred on line number: $line"
        }
    }

    writeToLog V "Checking if registry entry is present."
    writeToLog V "Registry Path:`r`n`t$registryPath"

    $regExists = Test-Path $registryPath

    If ($regExists -eq $true) {
        writeToLog V "Path still exists, will remove."

        try {
            Remove-Item $registryPath -force -ErrorAction Stop
        }
        catch {
            $msg = $_.Exception.Message
            $line = $_.InvocationInfo.ScriptLineNumber
            writeToLog W "Unable to remove path from registry, due to:`r`n`t$msg"
            writeToLog V "This occurred on line number: $line"
        }
    } Else {
        writeToLog V "Registry Path no longer exists."
    }

    writeToLog V ("### Completed running {0} function. ###`r`n" -f $MyInvocation.MyCommand)
}

function performEcosytemUninstall() {
	writeToLog V ("### Started running {0} function. ###" -f $MyInvocation.MyCommand)

    $ecoPath = "C:\Program Files (x86)\Solarwinds MSP\Ecosystem Agent\unins000.exe"

    If (!(Test-Path $ecoPath)) {
        writeToLog E "The uninstaller for the Ecosystem Agent doesn't exist."
        writeToLog W "Ecosystem Agent removal cannot proceed."
    } Else {

        writeToLog I "Now running the Ecosystem uninstaller."
        writeToLog I "Invoking the uninstaller from the following location:`r`n`t$ecoPath"

        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $ecoPath
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.UseShellExecute = $false
        $pinfo.Arguments = "/VERYSILENT"

        $installArgs = $pinfo.Arguments
        writeToLog V "Uninstall Arguments set: $installArgs"

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
        $p.WaitForExit()
        $script:exitCode = $p.ExitCode

        If ($exitCode -ne 0) {
            writeToLog W "Did not successfully perform uninstall, as Exit Code is: $exitCode"
        } Else {
            writeToLog I "Successfully performed uninstall, as the returned Exit Code is: $exitCode"
        }

        Start-Sleep 10
    }

    writeToLog V ("### Completed running {0} function. ###`r`n" -f $MyInvocation.MyCommand)
}

function writeToLog($state, $message) {

    $script:timestamp = "[{0:dd/MM/yy} {0:HH:mm:ss}]" -f (Get-Date)

	switch -regex -Wildcard ($state) {
		"I" {
			$state = "INFO"
            $colour = "Cyan"
		}
		"E" {
			$state = "ERROR"
            $colour = "Red"
		}
		"W" {
			$state = "WARNING"
            $colour = "Yellow"
		}
		"F"  {
			$state = "FAILURE"
            $colour = "Red"
        }
        "C"  {
			$state = "COMPLETE"
            $colour = "Green"
        }
        "V"  {
            If ($verboseMode -eq $true) {
                $state = "VERBOSE"
                $colour = "Magenta"
            } Else {
                return
            }
		}
		""  {
			$state = "INFO"
		}
		Default {
			$state = "INFO"
		}
     }

    Write-Host "$($timeStamp) - [$state]: $message" -ForegroundColor $colour
    Write-Output "$($timeStamp) - [$state]: $message" | Out-file $logFilePath -Append -ErrorAction SilentlyContinue
}

function main() {
# Main function, set to run other functions
    setupLogging
    validateUserInput
    getAgentPath
    # moveUninstaller
    stopAgentServices
    performUninstall
    postUninstall
    cleanupAgentData
    performEcosytemUninstall
}

main