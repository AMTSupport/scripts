#!ignore "3271b7a17cc1a89faeba83df9c07760c"
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
    $verbose = "Y",
    [int]$timeout = 30
)

function setupLogging() {
    $script:logFilePath = "C:\ProgramData\MspPlatform\Tech Tribes\AVDefenderCleanup\debug.log"
    
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

    [float]$script:currentVersion = 1.04
    writeToLog I "Started processing the avdCleanup script."
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
		$script:agentPresent = $false

		$script:localFolder = "C:\Program Files (x86)\N-able Technologies\Windows Agent\"
        writeToLog W "No Windows Agent located."

    } Else {
		$script:agentPresent = $true

		If (($script:localFolder -match '.+?\\$') -eq $false) {
			$script:localFolder = $script:localFolder + "\"
		}
	
		writeToLog I "Windows Agent install location found:`r`n`t$localFolder"
		writeToLog V "Registry location: `r`n`t$registryPath`r`n`t$registryName"
	}

	writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function downloadUninstaller() {
    writeToLog V ("### Started running {0} function. ###" -f $MyInvocation.MyCommand)

    # Download the Site Installation Package from new location
    $uninsUrl = "https://sis.n-able.com/GenericFiles/AVDefenderUninstallTool/7.4.3.146/UninstallToolSilent.exe"

    $script:downloadLocation = $logFolder
    $script:localFile = $uninsUrl.Split("/")[-1]

    $source = $uninsUrl
    $dest = $downloadLocation+$localFile

    If (Test-Path $dest) {
        writeToLog W "File already present, skipping download."

    } Else {

        writeToLog I "Downloading the following uninstaller:`r`n`t$localFile"
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

        writeToLog I "The $localFile uninstaller has downloaded successfully."
    }

    $script:uninstallerPath = $dest

    writeToLog V ("### Completed running {0} function. ###" -f $MyInvocation.MyCommand)
}

function stopServices() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)

	$array = @()
	$array += "Windows Agent Service"
	$array += "Windows Agent Maintenance Service"
	
	foreach ($serviceName in $array) {

		If (Get-Service $serviceName -ErrorAction SilentlyContinue) {
			writeToLog I "Detected the `'$serviceName`' Windows Service on the device, will now stop the service."

			try {
   				$script:stopService = Stop-Service -Name $serviceName -ErrorAction Stop -WarningAction SilentlyContinue
  			} catch {
				$msg = $_.Exception
				$line = $_.InvocationInfo.ScriptLineNumber
				writeToLog W "Failed to stop the `#$serviceName`# Windows Service, due to:`r`n`t$($msg.Message)"
				writeToLog V "This occurred on line number: $line"
				writeToLog V "Status:`r`n`t$($msg.Status)`r`nResponse:`r`n`t$($msg.Response)`r`nInner Exception:`r`n`t$($msg.InnerException)`r`n`r`nHResult: $($msg.HResult)`r`n`r`nTargetSite and StackTrace:`r`n$($msg.TargetSite)`r`n$($msg.StackTrace)`r`n"
			}

			writeToLog I "The `'$serviceName`' Windows Service is now stopped."

		} Else {
			writeToLog W "The `'$serviceName`' Windows Service was not found."
        }
	}

	writeToLog V ("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function performUninstall() {
    writeToLog V ("### Started running {0} function. ###" -f $MyInvocation.MyCommand)

    $switches = "/bdparams /SILENT /bruteForce /destructive"
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $uninstallerPath
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = $switches

    writeToLog V "Using switch: $switches"
    writeToLog V "Running the following uninstaller:`r`n`t$uninstallerPath"

    <#
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $p.WaitForExit()
    Start-Sleep 10
    $script:exitCode = $p.ExitCode
    
    If (($exitcode -eq 0)-or ($null -eq $exitcode)) {
        writeToLog I "Successfully returned exit code 0 from uninstall action."
    } Else {
        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()

        writeToLog F "Ran into a failure during uninstall, exit code returned: $exitcode"
        writeToLog F "Standard Output:`r`n`t$stdout"
        writeToLog F "Standard Error:`r`n`t$stderr"
    }
    #>


    writeToLog I "Timeout set to: $timeout seconds."

    $max_iterations = 1
    for ($i=0; $i -lt $max_iterations; $i++) {
        # $proc = Start-Process -filePath $uninstallerPath -ArgumentList $switches -workingdirectory $programtorunpath -PassThru
        $proc = Start-Process -filePath $uninstallerPath -ArgumentList $switches -PassThru

        # keep track of timeout event
        $timeouted = $null # reset any previously set timeout

        # wait up to x seconds for normal termination
        $proc | Wait-Process -Timeout $timeout -ErrorAction SilentlyContinue -ErrorVariable timeouted

        if ($timeouted) {
            # terminate the process
            # $proc | kill

           Get-Process | Where-Object {$_.ProcessName -like "uninstalltool*"} | stop-process -force

            # update internal error counter
        } elseif ($proc.ExitCode -ne 0) {
            # update internal error counter
        }
    }

    writeToLog V ("### Completed running {0} function. ###" -f $MyInvocation.MyCommand)
}

function cleanupFoldersAndKeys() {
    writeToLog V ("### Started running {0} function. ###" -f $MyInvocation.MyCommand)

    $array = @()
    $array += "HKLM:\SOFTWARE\Endpoint Security.remove"
    $array += "HKLM:\SOFTWARE\Bitdefender"
    $array += "HKLM:\SYSTEM\CurrentControlSet\Services\BdDci"
    $array += $localFolder + "config\AVDefenderConfig.xml"
    $array += $localFolder + "config\AVDefenderConfig.xml.backup"
    $array += $localFolder + "config\AVDefenderErrorManager.xml"
    $array += $localFolder + "config\AVDefenderErrorManager.xml.backup"

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
            writeToLog W "The $item doesn't exist, skipping."
        }
    }

writeToLog V ("### Completed running {0} function. ###" -f $MyInvocation.MyCommand)
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

function startServices() {
	writeToLog V ("Started running {0} function." -f $MyInvocation.MyCommand)

	$array = @()
	$array += "Windows Agent Service"
	$array += "Windows Agent Maintenance Service"
	
	foreach ($serviceName in $array) {

		If (Get-Service $serviceName -ErrorAction SilentlyContinue) {
			writeToLog I "Detected the `'$serviceName`' Windows Service on the device, will now start the service."

			try {
   				$script:startService = Start-Service -Name $serviceName -ErrorAction Stop -WarningAction SilentlyContinue
  			} catch {
				$msg = $_.Exception
				$line = $_.InvocationInfo.ScriptLineNumber
				writeToLog W "Failed to start the `'$serviceName`' Windows Service, due to:`r`n`t$($msg.Message)"
				writeToLog V "This occurred on line number: $line"
				writeToLog V "Status:`r`n`t$($msg.Status)`r`nResponse:`r`n`t$($msg.Response)`r`nInner Exception:`r`n`t$($msg.InnerException)`r`n`r`nHResult: $($msg.HResult)`r`n`r`nTargetSite and StackTrace:`r`n$($msg.TargetSite)`r`n$($msg.StackTrace)`r`n"
			}

			writeToLog I "The `'$serviceName`' Windows service has now started."

		} Else {
			writeToLog W "The `'$serviceName`' Windows Service was not found."
        }
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
    downloadUninstaller
    stopServices
    performUninstall
    cleanupFoldersAndKeys
    killAgentProcesses
    startServices

    exit 0
}
main