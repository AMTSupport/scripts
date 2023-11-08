#Requires -Version 5.1
#Requires -Modules ExchangeOnlineManagement
#Requires -PSEdition Core

Param (
    [Parameter()]
    [ParameterType]$RoomName = "Meeting Room",

    [Parameter()]
    [ParameterType]$RoomEmail = "meetingroom"
)

function New-Account {
    # New-Mailbox -DisplayName $RoomName -UserPrincipalName $Email -Password (ConvertTo-SecureString $Password -AsPlainText -Force)
}

function Set-Permissions {
    Set-MailboxFolderPermission -Identity "${RoomName}:\calendar" -User default -AccessRights ReadItems
}

function Set-Calender {
    Set-CalendarProcessing -Identity "$RoomName" -AutomateProcessing AutoAccept -AddOrganizerToSubject $true -DeleteComments $false -DeleteSubject $false
}

New-Account
Set-Permissions
Set-Calender
