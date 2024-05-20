<#
.SYNOPSIS
    A script to fix the scenario where the N-sight RMM Agent gets stuck in a loop.
.DESCRIPTION
    A script to fix the scenario where the N-sight RMM Agent gets stuck in a loop.
    This should be provided to partners only when this issue is present.
.NOTES
    File Name      : fixAgentUpdateLoop.ps1
    Author         : John Peterson
    Prerequisite   : None
    Version        : 1.0
    Disclaimer     : The sample scripts are not supported under any N-able support program or service.
                     The sample scripts are provided AS IS without warranty of any kind.
                     N-able further disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose.
                     The entire risk arising out of the use or performance of the sample scripts and documentation stays with you.
                     In no event shall N-able or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever
                     (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss)
                     arising out of the use of or inability to use the sample scripts or documentation.
#>

$script:logFileName = "FixWinAgentUpdateLoop.log"
$script:logFilePath = "C:\Technical Support"
$script:combinedPathAndAndName = "$($script:logFilePath)\$($script:logFileName)"

function writeToLog($state, $message) {

    $script:timestamp = "[{0:dd/MM/yy} {0:HH:mm:ss}]" -f (Get-Date)

    switch -regex -Wildcard ($state) {
        "I" {
            $state = "INFO"
        }
        "E" {
            $state = "ERROR"
        }
        "W" {
            $state = "WARNING"
        }
        "F"  {
            $state = "FAILURE"
        }
        "V"  {
            $state = "VERBOSE"
        }
        ""  {
            $state = "INFO"
        }
        Default {
            $state = "INFO"
        }
        }

    Write-Host "$($timeStamp) - [$state]: $message"
    Write-Output "$($timeStamp) - [$state]: $message" | Out-file $script:combinedPathAndAndName -Append
}

function createLogFileAndWorkingDirectory () {
    #Create the logFilePath
    if(!(test-path $script:logFilePath)) {
        try {
            New-Item -ItemType Directory -Path $script:logFilePath -ErrorAction Stop| Out-Null
            writeToLog V "Logfile Directory $($script:logFilePath) has been created."
        } catch {
            $errorMessage = "We have failed to create the folder $($logFilePath) which is the working directory of the script. Error thrown was: $($error[0])."
            writeToLog E $errorMessage
            exit 1
        }
    } else {
        writeToLog V "Logfile Directory $($script:logFilePath) has been created."
    }
    #Create the logFile in the logFilePath
    try {
        New-Item -ItemType File -Path $script:combinedPathAndAndName -ErrorAction Stop -Force | Out-Null
        writeToLog V "Log file $($script:logFileName) has been created."
    } catch {
        $errorMessage = "We have failed to create the file $script:logFileName which is logfile the script logs to. Error thrown was: $($error[0])."
        writeToLog E $errorMessage
        exit 1
    }
}

function stopService () {
    try {
        $service = get-service -name "Advanced Monitoring Agent" -ErrorAction stop
    } catch {
        writeToLog E "The Advanced Monitoring Agent service doesn't exist. Therefore this script will exit."
        exit 1
    }

    $script:existingStartType = ($service | Select-Object -Property StartType).StartType

    writeToLog V "Setting Service Startup Type to Disabled, to stop the Agent re-starting itself during maintenance."

    $service | Set-Service -StartupType Disabled

    writeToLog I "Stopping Service."

    $service | Stop-Service -ErrorAction SilentlyContinue

    $service = get-service -name "Advanced Monitoring Agent"

    if($service.status -ne "Stopped") {
        $script:needToCheckServiceAfterKillingProcesses = $true
        writeToLog V "The service is in state $($service.status) after attempting to be stopped. Will check service after stopping processes."
    } else {
        writeToLog V "The service is stopped."
    }
 }

function killProcesses () {
    writeToLog I "Ending processes."
    try {
        writeToLog V "Checking if process winagent.exe is still running."
        $process = get-process -ProcessName winagent -ErrorAction Stop
        writeToLog V "winagent.exe is still running. Attempting to stop."
        $process | Stop-Process -Force
        $process = get-process -ProcessName winagent -ErrorAction Stop
        writeToLog E "winagent.exe is still running. This device will need manual intervention."
        exit 1
    } catch {
        writeToLog V "winagent.exe isn't running. Moving on."
    }

    try {
        writeToLog V "Checking if process _new_winagent.exe is still running."
        $process = get-process -ProcessName _new_winagent -ErrorAction Stop
        writeToLog V "_new_winagent.exe is still running. Attempting to stop."
        $process | Stop-Process -Force
        writeToLog E "_new_winagent.exe is still running. This device will need manual intervention."
        exit 1
    } catch {
        writeToLog V "Process _new_winagent.exe isn't running. Moving on."
    }

    if($script:needToCheckServiceAfterKillingProcesses) {
        $service = get-service -name "Advanced Monitoring Agent"
        if($service.status -ne "Stopped") {
            writeToLog E "The service is in state $($service.status) after the processes were stopped. This shouldn't happen."
            exit 1
        } else {
            writeToLog V "The service is stopped."
        }
    }
}

function deleteStagingFolder () {
    writeToLog I "Deleting Staging folder contents."
    $AgentLocationGP = "\Advanced Monitoring Agent GP"
    $AgentLocation = "\Advanced Monitoring Agent"

    If((Get-WmiObject Win32_OperatingSystem).OSArchitecture -like "*64*"){
        #Check Agent Install Location
        $PathTester = "C:\Program Files (x86)" +  $AgentLocationGP + "\debug.log"
        If(!(Test-Path $PathTester)){
            $PathTester = "C:\Program Files (x86)" +  $AgentLocation + "\staging"
            Remove-item $PathTester\* -recurse -Force
        }
        Else {
            $PathTester = "C:\Program Files (x86)" + $AgentLocationGP + "\staging"
            Remove-item $PathTester\* -recurse -Force
        }
    }
    Else {
        #Check Agent Install Location
        $PathTester = "C:\Program Files" +  $AgentLocationGP + "\debug.log"
        If(!(Test-Path $PathTester)){
            $PathTester = "C:\Program Files" +  $AgentLocation + "\staging"
            Remove-item $PathTester\* -recurse -Force
        }
        Else {
            $PathTester = "C:\Program Files" + $AgentLocationGP + "\staging"
            Remove-item $PathTester\* -recurse -Force
        }
    }
    writeToLog V "Staging folder contents have been deleted."
}

function restartAgentService () {
    try {
        $service = get-service -name "Advanced Monitoring Agent" -ErrorAction stop
    } catch {
        writeToLog E "The Advanced Monitoring Agent service doesn't exist. Even though it existed the last time we checked. This is a very rare edge case where the Agent has probably been uninstalled in this window."
        exit 1
    }
    writeToLog V "Setting Service Startup Type to $script:existingStartType."
    $service | Set-Service -StartupType $script:existingStartType

    writeToLog I "Starting Agent Service."
    $service | Start-Service
}


createLogFileAndWorkingDirectory
stopService
killProcesses
deleteStagingFolder
restartAgentService
