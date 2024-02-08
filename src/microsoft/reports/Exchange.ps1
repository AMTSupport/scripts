function Get-SharedMailboxes {
    Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize:Unlimited | ForEach-Object { Get-MailboxPermission -Identity $_.WindowsEmailAddress } | Select-Object Identity, User, AccessRights | Where-Object { ($_.user -like '*@*') } | Export-Csv sharedfolders.csv -NoTypeInformation
    Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize:Unlimited | Where-Object { $_.DisplayName -notlike 'zArchived - *' } | ForEach-Object { Get-MailboxFolderPermission -Identity $_.PrimarySmtpAddress } | Select-Object Identity, User, AccessRights | Export-Csv sharedfolders.csv -NoTypeInformation -Append
}

function Get-DistributionGroups {
    Get-DistributionGroup -ResultSize:Unlimited | ForEach-Object { Get-DistributionGroupMember -Identity $_.PrimarySmtpAddress } | Select-Object Identity, DisplayName, PrimarySmtpAddress, RecipientType | Where-Object { ($_.PrimarySmtpAddress -like '*@*') } | Export-Csv distributiongroups.csv -NoTypeInformation
}
