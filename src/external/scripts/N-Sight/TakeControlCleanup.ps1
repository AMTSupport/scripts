#!ignore "3b422ca6988d468f60e12d30418eaaf8"
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
	$script:logFilePath = "C:\ProgramData\MspPlatform\Tech Tribes\Feature Cleanup Utility\debug.log"

	$script:logFolder = Split-Path $logFilePath
	$script:logFile = Split-Path $logFilePath -Leaf

	If (($logFolder -match '.+?\\$') -eq $false) {
        $script:logFolder = $logFolder + "\"
    }

	$script:scriptLocation = $logFolder + "TakeControlCleanup.ps1"

    [float]$script:currentVersion = 1.02
    writeToLog I "Started processing the Take Control Cleanup script."
    writeToLog I "Running script version: $currentVersion"
}

function validateUserInput() {
    # Handles input params and determines if log output is verbose
    If ($verbose.ToLower() -eq "y") {
        $script:verboseMode = $true
        writeToLog V "You have defined to have the script output the verbose log entries."
    } Else {
        $script:verboseMode = $false
        writeToLog I "Will output logs in regular mode."
    }

    writeToLog V "Input Parameters have been successfully validated."
    writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function initialSetup() {
    writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)

    $osVersion = (Get-WmiObject Win32_OperatingSystem).Caption
    # Workaround for WMI timeout or WMI returning no data
    If (($null -eq $osVersion) -or ($OSVersion -like "*OS - Alias not found*")) {
        $osVersion = (Get-Item "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").GetValue('ProductName')
    }
    writeToLog I "Detected Operating System:`r`n`t$OSVersion"
    
    $osArch = (Get-WmiObject Win32_OperatingSystem).OSArchitecture
    writeToLog I "Detected Operating System Aarchitecture: $osArch"

    $psVersion = $PSVersionTable.PSVersion
    writeToLog I "Detected PowerShell Version:`r`n`t$psVersion"

    $dotNetVersion = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP' -Recurse | Get-ItemProperty -Name version -EA 0 | Where-Object { $_.PSChildName -Match '^(?!S)\p{L}'} | Select-Object PSChildName, version

    foreach ($i in $dotNetVersion) {
        writeToLog I ".NET Version: $($i.PSChildName) = $($i.Version)"
    }

    writeToLog I "Setting TLS to version 1.2."
    # Set security protocol to TLS 1.2 to avoid TLS errors
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $tlsValue = [Net.ServicePointManager]::SecurityProtocol

    writeToLog V "Confirming TLS Value set:`r`n`t$tlsValue"

    writeToLog I "Checking if device has TLS 1.2 Cipher Suites."
    [System.Collections.ArrayList]$enabled = @()

    $cipherslists = @('TLS_DHE_RSA_WITH_AES_128_GCM_SHA256','TLS_DHE_RSA_WITH_AES_256_GCM_SHA384','TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256','TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384')
    $ciphersenabledkey = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Cryptography\Configuration\Local\SSL\00010002\' | Select-Object -ExpandProperty Functions
    
    ForEach ($a in $ciphersenabledkey) {
        If ($cipherslists -eq $a){
            $enabled.Add($a) | Out-Null
        }
    }
    
    If ($enabled.count -ne 0) {
        writeToLog I "Cipher Suite(s) found:"
        Foreach ($i in $enabled) {
            writeToLog I "Detected Cipher: $i"
        }
    } Else {
        writeToLog W "Device is not fully patched, no secure Cipher Suite(s) were found."
    }
    
    writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function getAgentPath() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)
	
    $array = @()
	$array += "GetSupportService_LOGICnow"
	$array += "GetSupportService_N-Central"

    ForEach ($key in $array) {

        $regPath = "HKLM:\SOFTWARE\WOW6432Node\Multiplicar Negocios\BeAnyWhere Support Express\" + $key

        If (Test-Path $regPath) {
            writeToLog V "Registry entry exists for $key"

            try {
                $Keys = Get-ItemProperty $regPath -ErrorAction Stop
            } catch {
                $msg = $_.Exception
                $line = $_.InvocationInfo.ScriptLineNumber
                writeToLog W "Failed to read Item Properties for registry entry $key, due to:`r`n`t$($msg.Message)"
                writeToLog V "This occurred on line number: $line"
                writeToLog V "Status:`r`n`t$($msg.Status)`r`nResponse:`r`n`t$($msg.Response)`r`nInner Exception:`r`n`t$($msg.InnerException)`r`n`r`nHResult: $($msg.HResult)`r`n`r`nTargetSite and StackTrace:`r`n$($msg.TargetSite)`r`n$($msg.StackTrace)`r`n"
            }
        
            ForEach ($Item in $Keys) {
                $script:installPath = $Item.Install_Dir
                $script:installedVersion = $Item.Version
            }

            If (!(Test-Path $installPath)) {
                writeToLog W "The Take Control install location is pointing to a path that doesn't exist."
                writeToLog I "Will continue with post-cleanup."

                $script:installPath = $logFolder
                $script:downloadUninstaller = $true
                downloadTCUninstaller
            } Else {
                writeToLog V "Install Path:`r`n`t$installPath"
                writeToLog V "Installed Version:`r`n`t$installedVersion"
            
                If (($installPath -match '.+?\\$') -eq $false) {
                    $script:installPath = $script:installPath + "\"
                }
            
                writeToLog V "Take Control Folder located:`r`n`t$installPath"
            
                $script:uninstallerPath = $installPath + "uninstall.exe"
            
                If (!(Test-Path $uninstallerPath)) {
                    writeToLog W "Unable to locate uninstall.exe on the device."
                    writeToLog W "Uninstaller Path:`r`n`t$uninstallerPath"
                    writeToLog W "Will download uninstall.exe since it is missing."
                    $script:downloadUninstaller = $true
                    downloadTCUninstaller
                } Else {
                    writeToLog V "Confirmed uninstall.exe is present on the device:`r`n`t$uninstallerPath"
                }
            }
    
            clearFileLocks
            removeTmpUninstaller
            performUninstall

        } Else {
            writeToLog W "The $key entry does not exist in registry."
        }
    }

	writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function clearFileLocks() {
    # Detect and remove _installing/_uninstalling.lock files prior to cleanup
    writeToLog V ("### Started running {0} function. ###" -f $MyInvocation.MyCommand)

    $script:installLockFile = $installPath + "*installing.lock"
    $script:uninstallLockFile = $installPath + "*uninstalling.lock"

    writeToLog I "Testing if _installing.lock is present on the device, using the following path:`r`n`t$installLockFile"

    If (Test-Path $installLockFile) {
        writeToLog W "Detected _installing.lock on the device."
        $script:installLockCreation = (Get-Item $installLockFile).LastWriteTime.DateTime
        writeToLog W "This was created at: $installLockCreation"
        writeToLog W "Will now forcibly remove .lock file."

        try {
            Remove-Item $installLockFile -Force -ErrorAction Stop
        } catch {
            $msg = $_.Exception
            $line = $_.InvocationInfo.ScriptLineNumber
            writeToLog W "Unable to delete the _installing.lock file, due to:`r`n`t$($msg.Message)"
            writeToLog V "This occurred on line number: $line"
            writeToLog V "Status:`r`n`t$($msg.Status)`r`nResponse:`r`n`t$($msg.Response)`r`nInner Exception:`r`n`t$($msg.InnerException)`r`n`r`nHResult: $($msg.HResult)`r`n`r`nTargetSite and StackTrace:`r`n$($msg.TargetSite)`r`n$($msg.StackTrace)`r`n"
        }

        If (Test-Path $installLockFile) {
            writeToLog W "The _installing.lock file is still present on the device."
        }

    } Else {
        writeToLog I "The _installing.lock file was not found on the device."
    }

    writeToLog V "Testing if _uninstalling.lock is present on the device, using the following path:`r`n`t$uninstallLockFile"

    If (Test-Path $uninstallLockFile) {
        writeToLog W "Detected _uninstalling.lock on the device."
        $script:uninstallLockCreation = (Get-Item $uninstallLockFile).LastWriteTime.DateTime
        writeToLog W "This was created at: $uninstallLockCreation"
        writeToLog W "Will now forcibly remove .lock file."

        try {
            Remove-Item $uninstallLockFile -Force -ErrorAction Stop
        } catch {
            $msg = $_.Exception
            $line = $_.InvocationInfo.ScriptLineNumber
            writeToLog W "Unable to delete the _installing.lock file, due to:`r`n`t$($msg.Message)"
            writeToLog V "This occurred on line number: $line"
            writeToLog V "Status:`r`n`t$($msg.Status)`r`nResponse:`r`n`t$($msg.Response)`r`nInner Exception:`r`n`t$($msg.InnerException)`r`n`r`nHResult: $($msg.HResult)`r`n`r`nTargetSite and StackTrace:`r`n$($msg.TargetSite)`r`n$($msg.StackTrace)`r`n"
        }

        If (Test-Path $installLockFile) {
            writeToLog W "The _uninstalling.lock file is still present on the device."
        }

    } Else {
        writeToLog I "The _uninstalling.lock file was not found on the device."
    }

    writeToLog V ("### Completed running {0} function. ###" -f $MyInvocation.MyCommand)
}

function removeTmpUninstaller() {
    # Detect and remove _iu14D2N.tmp if present
    writeToLog V ("### Started running {0} function. ###" -f $MyInvocation.MyCommand)

    # If '_iu14D2N.tmp' is present on the device, then we will try to kill it
    try {
        $uninsLockProcTest = Get-Process -ProcessName "_iu*" -ErrorAction Stop
    } catch {
        $msg = $_.Exception
        $line = $_.InvocationInfo.ScriptLineNumber
        writeToLog W "Failed to detect uninstaller lock process, due to:`r`n`t$($msg.Message)"
        writeToLog V "This occurred on line number: $line"
        writeToLog V "Status:`r`n`t$($msg.Status)`r`nResponse:`r`n`t$($msg.Response)`r`nInner Exception:`r`n`t$($msg.InnerException)`r`n`r`nHResult: $($msg.HResult)`r`n`r`nTargetSite and StackTrace:`r`n$($msg.TargetSite)`r`n$($msg.StackTrace)`r`n"
    }

    If ($null -ne $uninsLockProcTest) {
        writeToLog I "Detected the $uninsLockProcTest process on the device, will terminate."

        try {
            Stop-Process $uninsLockProcTest -Force -ErrorAction Stop
        } catch {
            $msg = $_.Exception
            $line = $_.InvocationInfo.ScriptLineNumber
            writeToLog W "Failed to terminate the uninstaller lock process, due to:`r`n`t$($msg.Message)"
            writeToLog V "This occurred on line number: $line"
            writeToLog V "Status:`r`n`t$($msg.Status)`r`nResponse:`r`n`t$($msg.Response)`r`nInner Exception:`r`n`t$($msg.InnerException)`r`n`r`nHResult: $($msg.HResult)`r`n`r`nTargetSite and StackTrace:`r`n$($msg.TargetSite)`r`n$($msg.StackTrace)`r`n"
        }
    }

    $uninsLockPath = "$Env:USERPROFILE\AppData\Local\Temp\_iu*"

    If (Test-Path $uninsLockPath) {
        writeToLog W "Detected $uninsLockPath on the device, removing."

        try {
            Remove-Item "$Env:USERPROFILE\AppData\Local\Temp\_iu*" -Force -ErrorAction Stop
        } catch {
            $msg = $_.Exception
            $line = $_.InvocationInfo.ScriptLineNumber
            writeToLog W "Failed to remove the uninstaller lock file, due to:`r`n`t$($msg.Message)"
            writeToLog V "This occurred on line number: $line"
            writeToLog V "Status:`r`n`t$($msg.Status)`r`nResponse:`r`n`t$($msg.Response)`r`nInner Exception:`r`n`t$($msg.InnerException)`r`n`r`nHResult: $($msg.HResult)`r`n`r`nTargetSite and StackTrace:`r`n$($msg.TargetSite)`r`n$($msg.StackTrace)`r`n"
        }
    }

    writeToLog V "Uninstall lock not detected on the device, nor found as a running process/existing file."

    writeToLog V ("### Completed running {0} function. ###`r`n" -f $MyInvocation.MyCommand)
}

function downloadTCUninstaller() {
    writeToLog V ("### Started running {0} function. ###" -f $MyInvocation.MyCommand)

    # Download the Site Installation Package from new location
    $uninsUrl = "https://s3.amazonaws.com/new-swmsp-net-supportfiles/PermanentFiles/FeatureCleanup/Take%20Control/uninstall.exe"

    $script:downloadLocation = $installPath
    $script:localFile = "uninstaller.exe"

    $source = $uninsUrl
    $dest = $downloadLocation+$localFile

    writeToLog I "Downloading the Take Control uninstaller."
    writeToLog V "This is being directed to the following location:`r`n`t$dest"

    $wc = New-Object System.Net.WebClient

    try {
        $wc.DownloadFile($source, $dest)
    }
    catch [System.Net.WebException] {
        writeToLog F "The uninstaller failed to download, due to:"

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

    writeToLog I "The Take Control uninstaller has downloaded successfully."

    $script:uninstallerPath = $dest

    writeToLog V ("### Completed running {0} function. ###" -f $MyInvocation.MyCommand)
}

function performUninstall() {
    writeToLog V ("### Started running {0} function. ###" -f $MyInvocation.MyCommand)

    $switches = "/S"
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $uninstallerPath
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = $switches

    writeToLog V "Using switch: $switches"
    writeToLog V "Running the following uninstaller:`r`n`t$uninstallerPath"

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $p.WaitForExit()
    Start-Sleep 10
    $script:exitCode = $p.ExitCode
    
    If ($exitcode -eq 0) {
        writeToLog I "Successfully returned exit code 0 from uninstall action."
    } Else {
        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()

        writeToLog F "Ran into a failure during uninstall, exit code returned: $exitcode"
        writeToLog F "Standard Output:`r`n`t$stdout"
        writeToLog F "Standard Error:`r`n`t$stderr"
        writeToLog F "Failing script."
        Exit 1001
    }

    $timeoutInSecs = 600
    writeToLog V "Timeout set to $timeoutInSecs seconds."

    writeToLog V "Starting stopwatch."
    $sw = [Diagnostics.Stopwatch]::StartNew()
    
    while (($sw.Elapsed.TotalSeconds -lt $timeoutInSecs) -and (Test-Path $uninstallLockFile)) {
        $result = Test-Path $uninstallLockFile
        writeToLog V "Current uninstall timespan: $($sw.Elapsed.TotalSeconds) seconds."
        Start-Sleep 10
        writeToLog V "The _uninstalling.lock file is still present on the device (File Exists = $result)."
    }
    writeToLog V "Lock file no longer exists."
    $sw.Stop()
    writeToLog V "Uninstall action took $($sw.Elapsed.Seconds) seconds to complete."

    writeToLog V ("### Completed running {0} function. ###" -f $MyInvocation.MyCommand)
}

function removeMSPAProcesses() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)

    $array = @()
	$array += "BASupSrvc"
	$array += "BASupSrvcCnfg"
	$array += "BASupSrvcUpdater"
	$array += "BASupTSHelper"
	$array += "BASupClpHlp"

    ForEach ($process in $array) {
        If (Get-Process $process -ErrorAction SilentlyContinue) {
            writeToLog I "Detected the $process process on the device, will now terminate."

            try {
                Stop-Process -Name $process -Force -ErrorAction Stop
            } catch {
                $msg = $_.Exception
                $line = $_.InvocationInfo.ScriptLineNumber
                writeToLog W "The process could not be terminated, due to:`r`n`t$($msg.Message)"
                writeToLog V "This occurred on line number: $line"
                writeToLog V "Status:`r`n`t$($msg.Status)`r`nResponse:`r`n`t$($msg.Response)`r`nInner Exception:`r`n`t$($msg.InnerException)`r`n`r`nHResult: $($msg.HResult)`r`n`r`nTargetSite and StackTrace:`r`n$($msg.TargetSite)`r`n$($msg.StackTrace)`r`n"
            }

        } Else {
           writeToLog I "The $process process does not exist on the device."
        }
    }

	writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function removeMSPAServices() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)
	
	$array = @()
	$array += "BASupportExpressStandaloneService_LOGICnow"
	$array += "BASupportExpressSrvcUpdater_LOGICnow"
    $array += "BASupportExpressStandaloneService_N_Central"
    $array += "BASupportExpressSrvcUpdater_N_Central"
	
	ForEach ($serviceName in $array) {
		If (Get-Service $serviceName -ErrorAction SilentlyContinue) {
			writeToLog I "Detected the $serviceName service on the device, will now remove service."
			  
			try {
   				Stop-Service -Name $serviceName -ErrorAction Stop
   				sc.exe delete $serviceName -ErrorAction Stop
  			} catch {
   				writeToLog I "The service cannot be removed automatically. Please remove manually."
   				$removalError = $error[0]
				writeToLog I "Exception from removal attempt is: $removalError" 
			}
			writeToLog I "$serviceName service is now removed."
		} Else {
  			writeToLog I "$serviceName service does not exist on the device."
		 }
	}

	writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function removeMSPAFoldersAndKeys() {
    writeToLog V ("### Started running {0} function. ###" -f $MyInvocation.MyCommand)

	$array = @()
    $array += "C:\Program Files (x86)\Take Control Agent"
    $array += "C:\Program Files (x86)\BeAnywhere Support Express\GetSupportService_N-Central"
    $array += "C:\Program Files (x86)\Take Control Agent_&lt;#INSTANCE_NAME#&gt;"
    $array += "C:\Program Files\Take Control Agent"
    $array += "C:\Program Files\BeAnywhere Support Express\GetSupportService_N-Central"
    $array += "C:\ProgramData\GetSupportService_LOGICnow"
    $array += "C:\ProgramData\GetSupportService_N-Central"
    $array += "C:\ProgramData\GetSupportService_LOGICNow_&lt;#INSTANCE_NAME#&gt;"
    $array += "HKLM:\SOFTWARE\WOW6432Node\Multiplicar Negocios\BACE_LOGICnow"
    $array += "HKLM:\SOFTWARE\WOW6432Node\Multiplicar Negocios\BACE_N-Central"
    $array += "HKLM:\SOFTWARE\WOW6432Node\Multiplicar Negocios\BeAnyWhere Support Express\GetSupportService_LOGICnow"
    $array += "HKLM:\SOFTWARE\WOW6432Node\Multiplicar Negocios\BeAnyWhere Support Express\GetSupportService_N-Central"
    
	ForEach ($item in $Array) {
		If (Test-Path $item) {
			writeToLog V "Detected $item, foribly removing item."
		
            try {
				Remove-Item $item -Recurse -Force -ErrorAction Stop
			} catch {
                $msg = $_.Exception
                $line = $_.InvocationInfo.ScriptLineNumber
                writeToLog W "The item $item exists but cannot be removed, due to:`r`n`t$($msg.Message)"
                writeToLog V "This occurred on line number: $line"
                writeToLog V "Status:`r`n`t$($msg.Status)`r`nResponse:`r`n`t$($msg.Response)`r`nInner Exception:`r`n`t$($msg.InnerException)`r`n`r`nHResult: $($msg.HResult)`r`n`r`nTargetSite and StackTrace:`r`n$($msg.TargetSite)`r`n$($msg.StackTrace)`r`n"
			}
		} Else {
			writeToLog V "The $item doesn't exist, skipping."
		}
	}

    writeToLog V ("### Completed running {0} function. ###" -f $MyInvocation.MyCommand)
}

function postRuntime() {
	try {
		Remove-Item $scriptLocation -Force -ErrorAction SilentlyContinue
	}
	catch {
	}

	try {
		Remove-Item $xmlLocation -Force -ErrorAction SilentlyContinue
	}
	catch {
	}
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
    setupLogging
    validateUserInput
    getAgentPath
    removeMSPAProcesses
    removeMSPAServices
    removeMSPAFoldersAndKeys
    postRuntime
}
main