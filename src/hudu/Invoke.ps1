# Function to get Bitwarden entry by name
function Get-BitwardenEntryByName {
    param (
        [string]$EntryName
    )

    # Use the Bitwarden CLI to get the entry by name
    $entry = bw list items --search "$EntryName" --pretty | ConvertFrom-Json

    # Return the entry
    return $entry
}

# Function to get OnePassword entry by name
function Get-OnePasswordEntryByName {
    param (
        [string]$EntryName
    )

    # Use the OnePassword CLI to get the entry by name
    $entry = op get item "$EntryName" --session my --output json

    # Return the entry
    return $entry
}

# Function to log in to a tenant and invoke the script block
function Invoke-TenantScriptBlock {
    param (
        [string]$TenantName,
        [string]$Username,
        [string]$Password,
        [string]$ScriptBlock
    )

    # Log in to the tenant using a browser
    

    # Invoke the script block
    Invoke-Command -ScriptBlock $ScriptBlock
}

# Main script

# Get all Bitwarden entries that start with "O365 admin"
$bitwardenEntries = Get-BitwardenEntryByName "O365 admin"

# Loop through each Bitwarden entry
foreach ($entry in $bitwardenEntries) {
    # Get the tenant details from the Bitwarden entry
    $tenantName = $entry.Name
    $username = $entry.Username

    # Get the password from OnePassword using the same name as the Bitwarden entry
    $passwordEntry = Get-OnePasswordEntryByName $tenantName
    $password = $passwordEntry.details.password

    # Invoke the script block for the tenant
    Invoke-TenantScriptBlock -TenantName $tenantName -Username $username -Password $password -ScriptBlock {
        # Your script block code goes here
    }
}
