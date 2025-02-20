#!ignore "a659a16e1fec9fdf1933507d4019dd6d"
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
    $script:logFilePath = "C:\ProgramData\MspPlatform\Tech Tribes\Windows Agent Cleanup\debug.log"
	
	$script:logFolder = Split-Path $logFilePath
	$script:logFile = Split-Path $logFilePath -Leaf

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
    
    If (($logFolder -match '.+?\\$') -eq $false) {
        $script:logFolder = $logFolder + "\"
    }

	writeToLog I "Running script version: 1.08."
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

function getAgentPath() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)

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
        If ($Item.DisplayName -like "Windows Agent") {
            $script:localFolder = $Item.installLocation
            $script:registryPath = $Item.PsPath
            $registryName = $Item.PSChildName
			$script:uninstallString = $Item.UninstallString
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
		If ($Item.DisplayName -like "Windows Agent") {
            $script:localFolder = $Item.installLocation
            $script:registryPath = $Item.PsPath
            $registryName = $Item.PSChildName
			$script:uninstallString = $Item.UninstallString
            $registryDisplayName = $Item.DisplayName
            $registryVersion = $Item.DisplayVersion
            $registryInstallDate = $Item.InstallDate
            break
        }
	}

    If (!$script:localFolder) {
        writeToLog W "No Windows Agent located."
		writeToLog W "No uninstall can be performed but will carry on with the cleanup."
		$script:agentPresent = $false
		$script:localFolder = "C:\Program Files (x86)\N-able Technologies\Windows Agent\"
    } Else {
		$script:agentPresent = $true

		If (($script:localFolder -match '.+?\\$') -eq $false) {
			$script:localFolder = $script:localFolder + "\"
		}
	
		writeToLog I "Agent install location found:`r`n`t$localFolder"
		writeToLog V "Registry location: `r`n`t$registryPath`r`n`t$registryName"
	}

	writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function stopServices() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)

	$array = @()
	$array += "Windows Agent Service"
	$array += "Windows Agent Maintenance Service"
	
	foreach ($serviceName in $array) {

		If (Get-Service $serviceName -ErrorAction SilentlyContinue) {
			writeToLog I "Detected the $serviceName service on the device, will now stop the service."

			try {
   				$script:stopService = Stop-Service -Name $serviceName -ErrorAction Stop
  			} catch {
				$msg = $_.Exception
				$line = $_.InvocationInfo.ScriptLineNumber
				writeToLog W "Failed to remove Windows Agent folder, due to:`r`n`t$($msg.Message)"
				writeToLog V "This occurred on line number: $line"
				writeToLog V "Status:`r`n`t$($msg.Status)`r`nResponse:`r`n`t$($msg.Response)`r`nInner Exception:`r`n`t$($msg.InnerException)`r`n`r`nHResult: $($msg.HResult)`r`n`r`nTargetSite and StackTrace:`r`n$($msg.TargetSite)`r`n$($msg.StackTrace)`r`n"
			}

			writeToLog I "$serviceName service is now stopped."

		} Else {
			writeToLog W "$serviceName service was not found."
	   }
		
	}

	writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function runUninstaller() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)

	$uninsString = ($script:uninstallString -split 'MsiExec.exe ')[1]

	If ($uninsString.length -gt 0) {
		$argumentList = $uninsString + " /qn /norestart"
		writeToLog I  "Starting MSI Uninstaller."
		writeToLog V "Argument list confirming msi uninstall string:`r`n`t$argumentList"
		
		$uninstallExitCode = (Start-Process -FilePath msiexec.exe -ArgumentList $argumentList -Wait -Passthru).ExitCode
	
		writeToLog I "Uninstall process has now been completed."
	
		If ($uninstallExitCode -ne 0) {
			writeToLog W "Did not successfully perform uninstall, as Exit Code is: $uninstallExitCode"
		} Else {
			writeToLog I "Successfully performed uninstall, as the returned Exit Code is: $uninstallExitCode"
		}
	} Else {
		writeToLog V "Uninstall String length is: $($uninsString.length)"
		writeToLog V "Uninstall cannot occur, will contiunue with cleanup."
	}

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

	$pmeFolder = "C:\Program Files (x86)\SolarWinds MSP\"

	$hash = @{
		"$($pmeFolder)PME\unins000.exe" = "https://s3.amazonaws.com/new-swmsp-net-supportfiles/PermanentFiles/PMECleanup_Repository/patchmanunins000.dat";
		"$($pmeFolder)CacheService\unins000.exe" = "https://s3.amazonaws.com/new-swmsp-net-supportfiles/PermanentFiles/PMECleanup_Repository/cacheunins000.dat";
		"$($pmeFolder)RpcServer\unins000.exe" = "https://s3.amazonaws.com/new-swmsp-net-supportfiles/PermanentFiles/PMECleanup_Repository/rpcunins000.dat"
	}
   
	foreach ($key in $hash.Keys) {
		if (Test-Path $key) {
			$datItem = $key
			$datItem = $datItem -replace "exe","dat"

			if (!(Test-Path $datItem)) {
				writeToLog W "Dat file not found. Will attempt downloading."
   				downloadFileToLocation $hash[$key] $datItem 
				   
				if (!(Test-Path $datItem)) {
					writeToLog F "Unable to download dat file for uninstaller to run."
					writeToLog F "PME must be removed manually. Failing script."
    				exit 1001
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

	$pmeFolder = "C:\Program Files (x86)\MspPlatform\"

	$hash = @{
		"$($pmeFolder)PME\unins000.exe" = "https://s3.amazonaws.com/new-swmsp-net-supportfiles/PermanentFiles/PMECleanup_Repository/patchmanunins000.dat";
		"$($pmeFolder)FileCacheServiceAgent\unins000.exe" = "https://s3.amazonaws.com/new-swmsp-net-supportfiles/PermanentFiles/PMECleanup_Repository/cacheunins000.dat";
		"$($pmeFolder)RequestHandlerAgent\unins000.exe" = "https://s3.amazonaws.com/new-swmsp-net-supportfiles/PermanentFiles/PMECleanup_Repository/rpcunins000.dat"
	}
   
	foreach ($key in $hash.Keys) {
		if (Test-Path $key) {
			$datItem = $key
			$datItem = $datItem -replace "exe","dat"

			if (!(Test-Path $datItem)) {
				writeToLog W "Dat file not found. Will attempt downloading."
   				downloadFileToLocation $hash[$key] $datItem 
				   
				if (!(Test-Path $datItem)) {
					writeToLog F "Unable to download dat file for uninstaller to run."
					writeToLog F "PME must be removed manually. Failing script."
    				exit 1001
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

function removeProcesses() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)

	try {
		$script:pmeProcess = Get-Process -processname "*PME*" -ErrorAction Stop
		$script:rpcProcess = Get-Process -processname "*RPC*" -ErrorAction Stop
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
   				$script:stopService = Stop-Service -Name $serviceName -ErrorAction Stop
   				$script:deleteService = sc.exe delete $serviceName -ErrorAction Stop
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

function killAgentProcesses() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)

	try {
		$script:runningProcesses = Get-Process * -ErrorAction Stop | Where-Object {$_.Path -like "C:\Program Files (x86)\N-able Technologies\Windows Agent\*"} | Select-Object Name,Path
	}
	catch {
		$msg = $_.Exception
		$line = $_.InvocationInfo.ScriptLineNumber
		writeToLog W "Failed to detect running processes, due to:`r`n`t$($msg.Message)"
		writeToLog V "This occurred on line number: $line"
		writeToLog V "Status:`r`n`t$($msg.Status)`r`nResponse:`r`n`t$($msg.Response)`r`nInner Exception:`r`n`t$($msg.InnerException)`r`n`r`nHResult: $($msg.HResult)`r`n`r`nTargetSite and StackTrace:`r`n$($msg.TargetSite)`r`n$($msg.StackTrace)`r`n"
	}

	If ($null -ne $runningProcesses) {
		writeToLog W "Found following process(es):`r`n`t $($runningProcesses.Name)"

		foreach ($process in $runningProcesses) {
			try {
				$process | Stop-Process -Force -ErrorAction Stop
			}
			catch {
				$msg = $_.Exception
				$line = $_.InvocationInfo.ScriptLineNumber
				writeToLog W "Failed to stop the process: $process, due to:`r`n`t$($msg.Message)"
				writeToLog V "This occurred on line number: $line"
				writeToLog V "Status:`r`n`t$($msg.Status)`r`nResponse:`r`n`t$($msg.Response)`r`nInner Exception:`r`n`t$($msg.InnerException)`r`n`r`nHResult: $($msg.HResult)`r`n`r`nTargetSite and StackTrace:`r`n$($msg.TargetSite)`r`n$($msg.StackTrace)`r`n"
			}
		}

		foreach ($lockFile in Get-ChildItem -Path "C:\Program Files (x86)\N-able Technologies\Windows Agent\*" -Include * -Recurse) {
			foreach ($process in $runningProcesses) {
				$process.Modules | Where-Object {$_.FileName -eq $lockFile} | Stop-Process -Force -ErrorAction SilentlyContinue
			}
		}
	} Else {
		writeToLog V "No processes are running that are tied to the Windows Agent."
	}

	writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function cleanupAgent() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)

	try {
		$script:agentPathTester = Test-Path $localFolder -ErrorAction SilentlyContinue
	}
	catch {
		$msg = $_.Exception
		$line = $_.InvocationInfo.ScriptLineNumber
		writeToLog W "Failed to locate the Windows Agent folder, due to:`r`n`t$($msg.Message)"
		writeToLog V "This occurred on line number: $line"
		writeToLog V "Status:`r`n`t$($msg.Status)`r`nResponse:`r`n`t$($msg.Response)`r`nInner Exception:`r`n`t$($msg.InnerException)`r`n`r`nHResult: $($msg.HResult)`r`n`r`nTargetSite and StackTrace:`r`n$($msg.TargetSite)`r`n$($msg.StackTrace)`r`n"
	}
	
    If ($agentPathTester -eq $false) {
        writeToLog I "Windows Agent installation folder ($localFolder) is not present."
    } Else {
		writeToLog I "Windows Agent folder is present ($localFolder), will attempt to remove."

		try {
			Remove-Item $localFolder -Recurse -Force -ErrorAction Stop
		}
		catch {
			$msg = $_.Exception
			$line = $_.InvocationInfo.ScriptLineNumber
			writeToLog W "Failed to remove Windows Agent folder, due to:`r`n`t$($msg.Message)"
			writeToLog V "This occurred on line number: $line"
			writeToLog V "Status:`r`n`t$($msg.Status)`r`nResponse:`r`n`t$($msg.Response)`r`nInner Exception:`r`n`t$($msg.InnerException)`r`n`r`nHResult: $($msg.HResult)`r`n`r`nTargetSite and StackTrace:`r`n$($msg.TargetSite)`r`n$($msg.StackTrace)`r`n"
		}
    }

	$script:agentFolder = Split-Path $localFolder

    $agentFolderExists = Test-Path $agentFolder
    
    If (($agentFolder -match '.+?\\$') -eq $false) {
        $script:agentFolder = $agentFolder + "\"
    }

	If ($agentFolderExists -eq $false) {
        writeToLog I "Windows Agent folder ($agentFolder) is not present."
    } Else {
		writeToLog I "Windows Agent folder is present ($agentFolder), will attempt to remove."

		try {
			Remove-Item $agentFolder -Recurse -Force -ErrorAction Stop
		}
		catch {
			$msg = $_.Exception
			$line = $_.InvocationInfo.ScriptLineNumber
			writeToLog W "Failed to remove Windows Agent folder, due to:`r`n`t$($msg.Message)"
			writeToLog V "This occurred on line number: $line"
			writeToLog V "Status:`r`n`t$($msg.Status)`r`nResponse:`r`n`t$($msg.Response)`r`nInner Exception:`r`n`t$($msg.InnerException)`r`n`r`nHResult: $($msg.HResult)`r`n`r`nTargetSite and StackTrace:`r`n$($msg.TargetSite)`r`n$($msg.StackTrace)`r`n"
		}
    }

	$progDataFolder = "C:\ProgramData\N-Able Technologies\Windows Agent\"

	$progDataPpathTester = Test-Path $progDataFolder

    If ($progDataPpathTester -eq $false) {
        writeToLog I "Program Data folder ($progDataFolder) is not present."    
    } Else {
		try {
			Remove-Item $progDataFolder -Recurse -Force -ErrorAction Stop
		}
		catch {
			$msg = $_.Exception
			$line = $_.InvocationInfo.ScriptLineNumber
			writeToLog W "Failed to remove the ProgramData Windows Agent folder, due to:`r`n`t$($msg.Message)"
			writeToLog V "This occurred on line number: $line"
			writeToLog V "Status:`r`n`t$($msg.Status)`r`nResponse:`r`n`t$($msg.Response)`r`nInner Exception:`r`n`t$($msg.InnerException)`r`n`r`nHResult: $($msg.HResult)`r`n`r`nTargetSite and StackTrace:`r`n$($msg.TargetSite)`r`n$($msg.StackTrace)`r`n"
		}
    }

	writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function verifyAssetTag() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)

	writeToLog I "Checking if Asset tags exist."

    $class='NCentralAssetTag'
    $namespace='root\cimv2\NCentralAsset'
    $wmiAssetTag = Get-WmiObject -Namespace $namespace -Class $class

	$wmiAssetTagLength = ($wmiAssetTag.UUID).length
	
	If ($wmiAssetTagLength -eq 0) {
		writeToLog I "WMI Asset Tag does not exist."
	} Else {
		writeToLog I "WMI Asset Tag present on device."
		writeToLog I "WMI Asset Tag entry: $($wmiAssetTag.UUID)"
	}

    $path='HKLM:\SOFTWARE\N-able Technologies\NcentralAsset'
    $name='NcentralAssetTag'

	try {
		$regAssetTag = Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
	}
	catch {
	}
	
	$regAssetTagLength = ($regAssetTag.NcentralAssetTag).length

	If ($regAssetTagLength -eq 0) {
		writeToLog I "Registry Asset Tag does not exist."
	} Else {
		writeToLog I "Registry Asset Tag present on device."
		writeToLog I "Registry Asset Tag entry: $($regAssetTag.NcentralAssetTag)"
	}
	
	$xmlAssetTag = "C:\Program Files (x86)\N-able Technologies\NcentralAsset.xml"

	If (Test-Path $xmlAssetTag) {
		writeToLog I "The NcentralAsset.xml exists on the device."
    } Else {
		writeToLog I "The NcentralAsset.xml does not on the device."
	}
	
	writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function cleanupAssetTag() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)

	writeToLog I "Cleaning up Windows Agent Asset Tags."

    $class='NCentralAssetTag'
    $namespace='root\cimv2\NCentralAsset'
    Get-WmiObject -Namespace $namespace -Class $class | Remove-WmiObject

    $path='HKLM:\SOFTWARE\N-able Technologies\NcentralAsset'
    $name='NcentralAssetTag'

	try {
		Remove-ItemProperty -Path $path -Name $name -Force -ErrorAction SilentlyContinue
	}
	catch {
	}
	
	If (Test-Path -LiteralPath "C:\Program Files (x86)\N-able Technologies\NcentralAsset.xml") {
		try {
			Remove-Item -path "C:\Program Files (x86)\N-able Technologies\NcentralAsset.xml" -Force -ErrorAction SilentlyContinue
		}
		catch {
			$msg = $_.Exception
			$line = $_.InvocationInfo.ScriptLineNumber
			writeToLog W "Failed to remove NcentralAsset.xml, due to:`r`n`t$($msg.Message)"
			writeToLog V "This occurred on line number: $line"
			writeToLog V "Status:`r`n`t$($msg.Status)`r`nResponse:`r`n`t$($msg.Response)`r`nInner Exception:`r`n`t$($msg.InnerException)`r`n`r`nHResult: $($msg.HResult)`r`n`r`nTargetSite and StackTrace:`r`n$($msg.TargetSite)`r`n$($msg.StackTrace)`r`n"
		}
		writeToLog I "Successfully removed Asset Tags."
    }
	
	writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function cleanupTakeControl() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)

	writeToLog I "Uninstalling Take Control silently."

	If (Test-Path -LiteralPath "C:\Program Files (x86)\BeAnywhere Support Express\GetSupportService_N-Central\uninstall.exe") {
		try { 
			Start-Process -NoNewWindow -FilePath "C:\Program Files (x86)\BeAnywhere Support Express\GetSupportService_N-Central\uninstall.exe" -ArgumentList " /S"
		}
		catch {
			writeToLog W "Unable to find 64-bit installation, moving to 32-bit removal."
		}
		writeToLog I "Successfully Removed Take Control 64 bit."
	} ElseIf (Test-Path -LiteralPath "C:\Program Files\BeAnywhere Support Express\GetSupportService_N-Central\uninstall.exe") {
		Start-Process -NoNewWindow -FilePath "C:\Program Files\BeAnywhere Support Express\GetSupportService_N-Central\uninstall.exe" -ArgumentList " /S"
		writeToLog I "Successfully Removed Take Control 32 bit."
}

	writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function cleanupConfigBackup() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)
	
	writeToLog I "Removing ConnectionString_Agent.xml."

	$connectionStringXmlLocation = "C:\Program Files (x86)\N-able Technologies\Windows Agent\config\ConnectionString_Agent.xml"

	If (Test-Path $connectionStringXmlLocation) {
		try {
			Remove-Item -path $connectionStringXmlLocation -force -ErrorAction Stop
		}
		catch {
			$msg = $_.Exception
			$line = $_.InvocationInfo.ScriptLineNumber
			writeToLog W "Failed to remove NcentralAsset.xml, due to:`r`n`t$($msg.Message)"
			writeToLog V "This occurred on line number: $line"
			writeToLog V "Status:`r`n`t$($msg.Status)`r`nResponse:`r`n`t$($msg.Response)`r`nInner Exception:`r`n`t$($msg.InnerException)`r`n`r`nHResult: $($msg.HResult)`r`n`r`nTargetSite and StackTrace:`r`n$($msg.TargetSite)`r`n$($msg.StackTrace)`r`n"
		}
	} Else {
		writeToLog I "File does not exist."
	}

	writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
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

	If ($agentPresent -eq $true) {
		stopServices
		runUninstaller
	}

	writeToLog I "Agent removed. Will now perform auxiliary cleanup."
	determinePMEVersion

	If ($legacyPME -eq $true) {
		runPMEV1Uninstaller
	} Else {
		runPMEV2Uninstaller
	}
	
	removeProcesses
	removePMEServices
	removePMEFoldersAndKeys
	cleanupTakeControl
	cleanupConfigBackup
	killAgentProcesses
    cleanupAgent
	verifyAssetTag
    cleanupAssetTag
	verifyAssetTag
}
main