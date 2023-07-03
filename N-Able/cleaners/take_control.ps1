# '==================================================================================================================================================================
# 'Script to Cleanup and Uninstall Take Control
#'
# 'Disclaimer
# 'The sample scripts are not supported under any SolarWinds support program or service.
# 'The sample scripts are provided AS IS without warranty of any kind.
# 'SolarWinds further disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose.
# 'The entire risk arising out of the use or performance of the sample scripts and documentation stays with you.
# 'In no event shall SolarWinds or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever
# '(including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss)
# 'arising out of the use of or inability to use the sample scripts or documentation.
# '==================================================================================================================================================================
 
#Determines whether the OS is 32 or 64 bit

Param(
	[string]$forceRemove = "n"
)

$AgentLocationGP = "\Advanced Monitoring Agent GP\"
$AgentLocation = "\Advanced Monitoring Agent\"

function getAgentPath {

	$Keys = Get-ChildItem HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
	$Items = $Keys | Foreach-Object {Get-ItemProperty $_.PsPath }
	ForEach ($Item in $Items) {
		if ($Item.DisplayName -like "Advanced Monitoring Agent" -or $Item.DisplayName -like "Advanced Monitoring Agent GP"){
			$script:LocalFolder = $Item.InstallLocation
			break
		}
	}

	$Keys = Get-ChildItem HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall
	$Items = $Keys | Foreach-Object {Get-ItemProperty $_.PsPath }
	ForEach ($Item in $Items) {
		if ($Item.DisplayName -like "Advanced Monitoring Agent" -or $Item.DisplayName -like "Advanced Monitoring Agent GP"){
			$script:LocalFolder = $Item.InstallLocation
			break
		}
	}

	if(!$script:LocalFolder) {
		write-host "Agent Path not found. Exiting..."
		exit 1001
	}

	if(($script:LocalFolder -match '.+?\\$') -eq $false) {
		$script:LocalFolder = $script:LocalFolder + "\"
	}

	if(!(test-path $script:LocalFolder)) {
		write-host "The Agent Registry Entry is pointing to a path that doesn't exist. Falling back to legacy method of checking agent location."
		getAgentPath_Legacy
	}

	write-host "Agent Path is: " $script:LocalFolder
}

function getAgentPath_Legacy {

	If((Get-WmiObject Win32_OperatingSystem).OSArchitecture -like "*64*"){

	#Check Agent Install Location
	$PathTesterGP = "C:\Program Files (x86)" +  $AgentLocationGP + "\winagent.exe"
	$PathTester = "C:\Program Files (x86)" +  $AgentLocation + "\winagent.exe"
		
		If(Test-Path $PathTesterGP){
			$script:LocalFolder = "C:\Program Files (x86)" +  $AgentLocationGP
		}
		Elseif(Test-Path $PathTester) {
			$script:LocalFolder = "C:\Program Files (x86)" +  $AgentLocation
		} else {
			write-host "Agent Path not found. Exiting..."
			exit 1001
		}
	}

	Else {

	$PathTesterGP = "C:\Program Files" +  $AgentLocationGP + "\winagent.exe"
	$PathTester = "C:\Program Files" +  $AgentLocation + "\winagent.exe"
		
		If(Test-Path $PathTesterGP){
			$script:LocalFolder = "C:\Program Files" +  $AgentLocationGP
		}
		Elseif(Test-Path $PathTester) {
			$script:LocalFolder = "C:\Program Files" +  $AgentLocation
		} else {
			write-host "Agent Path not found. Exiting..."
			exit 1001
		}
		
	}

}

function isMSPAActive {
	#Gets the content of the Settings file
	[string]$filecontents = Get-Content ($script:LocalFolder + "settings.ini")

	#If the file contains the Patch settings already...
	If($filecontents -match "\[MSPCONNECT\][^\[\]]*ACTIVATED=1") {
		if($script:forceRemove.ToLower() -eq "y") {
			write-host "Take Control (MSP Anywhere) is still active on the Dashboard. However you have opted to force remove. Proceeding with cleanup..."
		} else {
			write-host "Take Control (MSP Anywhere) is still active on the Dashboard. Run this script after Take Control (MSP Anywhere) has been disabled on the dashboard."
			exit 1001
		}
	} else {
		write-host "Take Control (MSP Anywhere) is not active on the Dashboard. Proceeding with cleanup..."
	}
}

function runMSPAUninstaller {
	$array = @()
	$array += "C:\Program Files (x86)\Take Control Agent\uninstall.exe"
	$array += "C:\Program Files\Take Control Agent\uninstall.exe"
	foreach ($path in $array) {
		if (Test-Path $path) {
			write-host "$path Uninstaller exists - Running Uninstaller..."
			$pinfo = New-Object System.Diagnostics.ProcessStartInfo
			$pinfo.FileName = $path
			$pinfo.RedirectStandardError = $true
			$pinfo.RedirectStandardOutput = $true
			$pinfo.UseShellExecute = $false
			$pinfo.Arguments = "/S /R"
			$p = New-Object System.Diagnostics.Process
			$p.StartInfo = $pinfo
			$p.Start() | Out-Null
			$p.WaitForExit()
			$script:ExitCode = $p.ExitCode
			write-host "The Exit Code is:" $script:ExitCode
			start-sleep -s 15
			}
			else {
			write-host "Uninstaller doesn't exist - moving on..."
			}
	}
}

function removeMSPAFoldersAndKeys {
	$array = @()
	$array += "C:\Program Files (x86)\Take Control Agent"
	$array += "C:\Program Files\Take Control Agent"
	$array += "C:\ProgramData\GetSupportService_LOGICnow"
	$array += "HKLM:\SOFTWARE\Multiplicar Negocios\BeAnyWhere Support Express\GetSupportService_LOGICnow"
	foreach ($FolderLocation in $Array) {
		if (Test-Path $FolderLocation) {
			write-host "$FolderLocation exists. Removing item..."
			try {
				remove-item $folderLocation -recurse -force
			}
			catch  {
				Write-Host "The item $FolderLocation exists but cannot be removed automatically. Please remove manually."
				$removalError = $error[0]
				Write-Host "Exception from removal attempt is: $removalError" 
			}
		} else {
			write-host "$FolderLocation doesn't exist - moving on..."
		}
	}
}

function terminateMSPAProcesses {
	$array = @()
	$array += "BASupSrvc"
	$array += "BASupSrvcCnfg"
	$array += "BASupSrvcUpdater"
	$array += "BASupTSHelper"
	$array += "BASupClpHlp"
	foreach ($processName in $array) {
		$processObj = get-process -Name $processName -ErrorAction SilentlyContinue
		if ($processObj) {
			write-host "$processName exists. Killing Process..."
			try {
				$processObj | Stop-Process -Force -ErrorAction Stop
			} catch {
				"The process cannot be killed automatically. Please kill manually."
				$removalError = $error[0]
				Write-Host "Exception from removal attempt is: $removalError" 
			}
		} else {
			write-host "$processName doesn't exist."
		}
	}
	
}

function removeMSPAServices {
	$array = @()
	$array += "BASupportExpressStandaloneService_LOGICnow"
	$array += "BASupportExpressSrvcUpdater_LOGICnow"
	foreach ($serviceName in $array) {
		If (Get-Service $serviceName -ErrorAction SilentlyContinue) {
			write-host "$serviceName service exists. Removing service..."
			try {
				Stop-service -Name $serviceName -ErrorAction Stop
				sc.exe delete $serviceName -ErrorAction Stop
			} catch {
				"The service cannot be removed automatically. Please remove manually."
				$removalError = $error[0]
				Write-Host "Exception from removal attempt is: $removalError" 
			}

		} Else {
			Write-Host "$serviceName service not found."
		}
	}
}
getAgentPath
isMSPAActive
runMSPAUninstaller
terminateMSPAProcesses
removeMSPAServices
removeMSPAFoldersAndKeys






