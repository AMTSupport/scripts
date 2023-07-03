$DomainGUID = $args[0]

if ($DomainGUID -eq $null) {
    write-host "Error- Domain GUID not passed"
    Exit 1000
}

try {
    # Create the path manually if it doesn't exist already.
    new-item -itemtype directory -path "hklm:\Software\Policies\Microsoft\OneDrive" -force
} catch {
    write-host  "Error-Unable to create  hklm:\Software\Policies\Microsoft\OneDrive"
    Exit 1001
}

try {
    Set-ItemProperty -Path "hklm:\Software\Policies\Microsoft\OneDrive" -Name "AADJMachineDomainGuid" -Value $DomainGUID -Force
} catch {
    write-host "Error-Unable to set Domain GUID"
    exit 10002
}

Exit 0