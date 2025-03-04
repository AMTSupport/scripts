#!ignore {"Hash":"947e90c09c394e715cd00d2fc57e7e09","Patches":"..\\..\\patches\\PMECleanup_EnsureLogDirectory.patch"}
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
    $logFolderExists = Test-Path $logFolder
    $logFileExists = Test-Path $logFilePath

    If ($logFolderExists -eq $false) {
        New-Item -ItemType 'directory' -Path $logFolder | Out-Null
    }

    If ($logFileExists -eq $true) {
        Remove-Item $logFilePath -ErrorAction SilentlyContinue
        Start-Sleep 2
        New-Item -ItemType 'file' -Path $logFolder -Name $logFile | Out-Null
    } Else {
        New-Item -ItemType 'file' -Path $logFolder -Name $logFile | Out-Null
    }

	$script:scriptLocation = $logFolder + "PMECleanup.ps1"

	[float]$script:currentVersion = 1.14
	writeToLog I "Started processing the PME Cleanup script."
    writeToLog I "Running script version: $currentVersion"
}

function validateUserInput() {
# Ensures the provided input from user is valid
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
	
    try {
        $Keys = Get-ChildItem HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall -ErrorAction Stop
    } catch {
        writeToLog F "Error during the lookup of the CurrentVersion\Uninstall Path in the registry:"
        writeToLog F $_
		postRuntime
        Exit 1001
    }

    $Items = $Keys | Foreach-Object {
        Get-ItemProperty $_.PsPath
    }

    ForEach ($Item in $Items) {
        If ($Item.DisplayName -like "Patch Management Service Controller") {
			$script:localFolder = $Item.installLocation
            break
        }
    }

    try {
        $Keys = Get-ChildItem HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall -ErrorAction Stop
    } catch {
        writeToLog F "Error during the lookup of the WOW6432Node Path in the registry:"
        writeToLog F $_
    }
    
    $Items = $Keys | Foreach-Object {
        Get-ItemProperty $_.PsPath
    }
    
    ForEach ($Item in $Items) {
        If ($Item.DisplayName -like "*Patch Management Service Controller*") {
			$script:localFolder = $Item.installLocation
            break
        }
    }
    
    If (!$localFolder) {
		writeToLog F "PME installation not found."
		writeToLog F "Will do post-cleanup but marking script as failed."
		runPMEV2Uninstaller
		removeProcesses
		removePMEServices
		removePMEFoldersAndKeys
		postRuntime
 		Exit 1001
	}

   If (!(Test-Path $localFolder)) {
    	writeToLog F "The PME install location is pointing to a path that doesn't exist."
		runPMEV2Uninstaller
		removeProcesses
		removePMEServices
		removePMEFoldersAndKeys
		postRuntime
		Exit 1001
	}

    If (($localFolder -match '.+?\\$') -eq $false) {
        $script:localFolder = $script:localFolder + "\"
	}

	$script:pmeFolder = (Split-Path $localFolder) + "\"

	writeToLog V "PME Folder located:`r`n`t$pmeFolder"

	writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function determinePMEVersion() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)

    try {
        $pmeVersionRaw = Get-Process -Name *PME.Agent -FileVersionInfo | Select-Object ProductName,ProductVersion,FileVersion | Sort-Object -unique -ErrorAction Stop
    } catch {
        $msg = $_.Exception.Message
        $line = $_.InvocationInfo.ScriptLineNumber
        writeToLog F "Error occurred locating an applicable PME Agent process, due to:`r`n`t$msg"
        writeToLog V "This occurred on line number: $line"
        writeToLog F "Failing script."
		postRuntime
		Exit 1001
    }

	$pmeProductName = $pmeVersionRaw.ProductName
	$pmeProductVersion = $pmeVersionRaw.ProductVersion

	writeToLog V "Detected PME Version: $pmeProductVersion"

	If ($pmeProductName -eq "SolarWinds.MSP.PME.Agent") {
		writeToLog I "Detected installed PME Version is: $pmeProductVersion"
		$script:legacyPME = $true
	} ElseIf ($pmeProductName -eq "PME.Agent") {
		writeToLog I "Detected installed PME Version is: $pmeProductVersion"
		$script:legacyPME = $false
	}

	writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function runPMEV1Uninstaller() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)

	$hash = @{
		"$($pmeFolder)PME\unins000.exe" = "https://s3.amazonaws.com/new-swmsp-net-supportfiles/PermanentFiles/PMECleanup_Repository/patchmanunins000.dat";
		"$($pmeFolder)patchman\unins000.exe" = "https://s3.amazonaws.com/new-swmsp-net-supportfiles/PermanentFiles/PMECleanup_Repository/patchmanunins000.dat";
		"$($pmeFolder)CacheService\unins000.exe" = "https://s3.amazonaws.com/new-swmsp-net-supportfiles/PermanentFiles/PMECleanup_Repository/cacheunins000.dat";
		"$($pmeFolder)RpcServer\unins000.exe" = "https://s3.amazonaws.com/new-swmsp-net-supportfiles/PermanentFiles/PMECleanup_Repository/rpcunins000.dat"
	}
   
	foreach ($key in $hash.Keys) {
		If (Test-Path $key) {
			$datItem = $key
			$datItem = $datItem -replace "exe","dat"

			If (!(Test-Path $datItem)) {
				writeToLog W "Dat file not found. Will attempt downloading."
   				downloadFileToLocation $hash[$key] $datItem 
				   
				If (!(Test-Path $datItem)) {
					writeToLog F "Unable to download dat file for uninstaller to run."
					writeToLog F "PME must be removed manually. Failing script."
					postRuntime
    				Exit 1001
   				}
  			}

			writeToLog I "$key Uninstaller exists on the device. Now running uninstaller."

			$pinfo = New-Object System.Diagnostics.ProcessStartInfo
			$pinfo.FileName = $key
			$pinfo.RedirectStandardError = $true
			$pinfo.RedirectStandardOutput = $true
			$pinfo.UseShellExecute = $false
			$pinfo.Arguments = "/silent /SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART"
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

			Start-Sleep -s 5

 		} Else {
			writeToLog W "$key Uninstaller doesn't exist on the device." 
		}
	}
	writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function runPMEV2Uninstaller() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)

	$hash = @{
		"$($pmeFolder)PME\unins000.exe" = "https://s3.amazonaws.com/new-swmsp-net-supportfiles/PermanentFiles/PMECleanup_Repository/patchmanunins000.dat";
		"$($pmeFolder)patchman\unins000.exe" = "https://s3.amazonaws.com/new-swmsp-net-supportfiles/PermanentFiles/PMECleanup_Repository/patchmanunins000.dat";
		"$($pmeFolder)FileCacheServiceAgent\unins000.exe" = "https://s3.amazonaws.com/new-swmsp-net-supportfiles/PermanentFiles/PMECleanup_Repository/cacheunins000.dat";
		"$($pmeFolder)RequestHandlerAgent\unins000.exe" = "https://s3.amazonaws.com/new-swmsp-net-supportfiles/PermanentFiles/PMECleanup_Repository/rpcunins000.dat"
	}
   
	foreach ($key in $hash.Keys) {
		write-host "Checking $key"
		$keyName = (split-path $key).split('\')[-1]
		if (Test-Path $key) {
			$datItem = $key
			$datItem = $datItem -replace "exe","dat"

			write-host "Dat Item:`r`n`t$datItem"

			if (!(Test-Path $datItem)) {
				writeToLog W "Could not find the following dat file:`r`n`t$datItem"
				writeToLog W "Dat file not found. Will attempt downloading."
   				downloadFileToLocation $hash[$key] $datItem 
				   
				if (!(Test-Path $datItem)) {
					writeToLog F "Unable to download dat file for uninstaller to run."
					writeToLog F "PME must be removed manually. Failing script."
					postRuntime
    				exit 1001
   				}
  			}

			writeToLog I "$key Uninstaller exists on the device. Now running uninstaller."

			$pinfo = New-Object System.Diagnostics.ProcessStartInfo
			$pinfo.FileName = $key
			$pinfo.RedirectStandardError = $true
			$pinfo.RedirectStandardOutput = $true
			$pinfo.UseShellExecute = $false
			$pinfo.Arguments = "/silent /SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /LOG=`"C:\ProgramData\MspPlatform\Tech Tribes\Feature Cleanup Utility\$keyName-uninstall.log`""
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

			Start-Sleep -s 5

 		} Else {
			writeToLog W "$key Uninstaller doesn't exist on the device." 
		}
	}
	writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function removeProcesses() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)

	try {
		$script:pmeProcess = Get-Process -processname "*PME*" -ErrorAction Stop
		$script:rpcProcess = Get-Process -processname "*RequestHandlerAgent*" -ErrorAction Stop
		$script:cacheServiceProcess = Get-Process -processname "*Cache*" -ErrorAction Stop
    } catch {
		writeToLog E "Error detecting process:"
		writeToLog E $_
	}

	If ($null -ne $pmeProcess) {
		writeToLog I "Detected $pmeProcess on the device, removing."
		try {
			Stop-Process $pmeProcess -Force -ErrorAction Stop
		} catch {
			writeToLog E "Error stopping PME process:"
			writeToLog E $_
		}
	} Else {
		writeToLog I "Did not detect the PME process on the device."
	}

	If ($null -ne $rpcProcess) {
		writeToLog I "Detected $rpcProcess on the device, removing."
		try {
			Stop-Process $rpcProcess -Force -ErrorAction Stop
		} catch {
			writeToLog E "Error stopping RPC process:"
			writeToLog E $_
		}
	} Else {
		writeToLog I "Did not detect PME's RPC process on the device."
	}
	If ($null -ne $cacheServiceProcess) {
		writeToLog I "Detected $cacheServiceProcess on the device, removing."
		try {
			Stop-Process $cacheServiceProcess -Force -ErrorAction Stop
		} catch {
			writeToLog E "Error stopping Cache Service process:"
			writeToLog E $_
		}
	} Else {
		writeToLog I "Did not detect PME's Cache Service process on the device."
	}

	# If '_iu14D2N.tmp' is present on the device, then we will try to kill it
    try {
        $uninsLockProcTest = Get-Process -ProcessName "_iu*" -ErrorAction Stop
    } catch {
        writeToLog E "Error detecting uninstaller lock file, due to:"
        writeToLog E $_
    }

	If ($null -ne $uninsLockProcTest) {
		writeToLog I "Detected $uninsLockProcTest on the device, removing."
		try {
			Stop-Process $uninsLockProcTest -Force -ErrorAction Stop
		} catch {
			writeToLog E "Error stopping uninstall lock process:"
			writeToLog E $_
		}
	}

	$uninsLockPath = "$Env:USERPROFILE\AppData\Local\Temp\_iu*"
    $uninsLockPathTest = Test-Path $uninsLockPath

    If ($uninsLockPathTest -eq $true) {
		writeToLog I "Detected $uninsLockPath on the device, removing."
        Remove-Item "$Env:USERPROFILE\AppData\Local\Temp\_iu*" -Force
	}
	writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function downloadFileToLocation ($URL, $Location) {

	$wc = New-Object System.Net.WebClient
	
	try {
		 $wc.DownloadFile($URL, $Location)
	} catch {
		writeToLog E "Exception when downloading file $Location from source $URL."
	}
}

function removePMEServices() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)
	
	$array = @()
	$array += "PME.Agent.PmeService"
	$array += "SolarWinds.MSP.RpcServerService"
	$array += "SolarWinds.MSP.CacheService"
	
	foreach ($serviceName in $array) {

		If (Get-Service $serviceName -ErrorAction SilentlyContinue) {
			writeToLog I "Detected the $serviceName service on the device, will now remove service."
			  
			try {
   				$stopService = Stop-Service -Name $serviceName -ErrorAction Stop
   				$deleteService = sc.exe delete $serviceName -ErrorAction Stop
  			} catch {
   				writeToLog I "The service cannot be removed automatically. Please remove manually."
   				$removalError = $error[0]
				writeToLog I "Exception from removal attempt is: $removalError" 
			}
			writeToLog I "$serviceName service is now removed."
		} Else {
  			writeToLog W "$serviceName service not found."
		 }
	}
	writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function removePMEFoldersAndKeys() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)

	$array = @()
	$array += "C:\ProgramData\SolarWinds MSP\PME"
	$array += "C:\ProgramData\MspPlatform\PME"
	$array += "C:\ProgramData\MspPlatform\PME.Agent.PmeService"
	
	$array += "C:\ProgramData\SolarWinds MSP\SolarWinds.MSP.CacheService"
	$array += "C:\ProgramData\MspPlatform\SolarWinds.MSP.CacheService"
	$array += "C:\ProgramData\MspPlatform\FileCacheServiceAgent"

	$array += "C:\ProgramData\SolarWinds MSP\SolarWinds.MSP.Diagnostics"
	$array += "C:\ProgramData\SolarWinds MSP\SolarWinds.MSP.RpcServerService"
	$array += "C:\ProgramData\MspPlatform\SolarWinds.MSP.RpcServerService"
	$array += "C:\ProgramData\MspPlatform\RequestHandlerAgent"

	$array += "C:\Program Files (x86)\SolarWinds MSP\CacheService\"
	$array += "C:\Program Files (x86)\MspPlatform\FileCacheServiceAgent\"
	$array += "C:\Program Files (x86)\SolarWinds MSP\PME\"
	$array += "C:\Program Files (x86)\MspPlatform\PME\"
	$array += "C:\Program Files (x86)\SolarWinds MSP\RpcServer\"
	$array += "C:\Program Files (x86)\MspPlatform\RequestHandlerAgent\"

	$array += "$($script:LocalFolder)patchman"
	$array += "$($script:LocalFolder)CacheService"
	$array += "$($script:LocalFolder)RpcServer"
	$array += "$($script:LocalFolder)FileCacheServiceAgent"
	$array += "$($script:LocalFolder)RequestHandlerAgent"

	If ((Test-Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall") -eq $true) {
		$recurse = Get-ChildItem -path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
		
		foreach ($entry in $recurse) {
 			foreach ($key in Get-ItemProperty -path "Registry::$entry") {
  				if($key.DisplayName -eq "SolarWinds MSP RPC Server" -or $key.DisplayName -eq "Request Handler Agent" -or $key.DisplayName -eq "File Cache Service Agent" -or $key.DisplayName -eq "Patch Management Service Controller" -or $key.DisplayName -eq "SolarWinds MSP Patch Management Engine" -or $key.DisplayName -eq "SolarWinds MSP Cache Service") {
   					$temp = $entry.name -replace "HKEY_LOCAL_MACHINE", "HKLM:"
   					$array += $temp
  				}
 			}
		}
	}

	$recurse = Get-ChildItem -path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
	
	foreach ($entry in $recurse) {
 		foreach ($key in Get-ItemProperty -path "Registry::$entry") {
			if($key.DisplayName -eq "SolarWinds MSP RPC Server" -or $key.DisplayName -eq "Request Handler Agent" -or $key.DisplayName -eq "File Cache Service Agent" -or $key.DisplayName -eq "Patch Management Service Controller" -or $key.DisplayName -eq "SolarWinds MSP Patch Management Engine" -or $key.DisplayName -eq "SolarWinds MSP Cache Service") {
   				$temp = $entry.name -replace "HKEY_LOCAL_MACHINE", "HKLM:"
				$array += $temp
			}
 		}
	}

	foreach ($FolderLocation in $Array) {
		if (Test-Path $FolderLocation) {
			writeToLog I "$FolderLocation exists. Removing item..."
			  
			try {
   				remove-item $folderLocation -recurse -force
  			} catch {
   				writeToLog I "The item $FolderLocation exists but cannot be removed automatically. Please remove manually."
   				$removalError = $error[0]
   				writeToLog E "Exception from removal attempt is: $removalError" 
			}
 		} else {
  			writeToLog W "$FolderLocation doesn't exist - moving on..."
 		}
	}
	writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
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

function main(){
	setupLogging
	validateUserInput
	getAgentPath
	determinePMEVersion

	If ($legacyPME -eq $true) {
		runPMEV1Uninstaller
	} Else {
		runPMEV2Uninstaller
	}
	
	removeProcesses
    removePMEServices
    removePMEFoldersAndKeys
	
	writeToLog I "PME Cleanup now complete."
	postRuntime
}
main