#Requires -Version 5.1

<#
.DESCRIPTION
    Sets the default battery settings for a device to ensure they are able to be accessed for support,
    and don't put themselves to sleep while on power.
#>

Param (
    [Parameter(Mandatory=$false)]
    [switch]$dryrun = $false
)

# Defines the variables used to set the power settings
#
# If an item is set to $null this will not be changed;
# this is so that if a user has a preference for a setting, it will not be changed.
#
# The values for these settings are integers, that represent the number of minutes.
function prepareVariables() {
    $script:powerSettings = @{
        'OnBattery' = @{
            'Monitor' = $null
            'Sleep' = $null
            'Hibernate' = $null
        }
        'PluggedIn' = @{
            'Monitor' = $null
            'Sleep' = 0
            'Hibernate' = 0
        }
    }
}

function updatePowerSettings() {
    # Set the power settings for the device
    foreach ($powerMode in $powerSettings.keys) {
        Write-Host "Setting power settings for mode -> $($powerMode)"

        $powerModeArgument = if ($powerMode -eq 'OnBattery') { 'dc' } else { 'ac' }

        foreach ($powerSetting in $powerSettings[$powerMode].keys) {
            $powerSettingValue = $powerSettings[$powerMode][$powerSetting]

            if ($null -eq $powerSettingValue) {
                Write-Host "Leaving $powerSetting for $powerMode as is."
                continue
            }

            Write-Host "Setting $($powerSetting) to $($powerSettingValue) when $($powerMode)"

            $powerSettingArgument = switch ($powerSetting) {
                "Sleep" { "standby" }
                Default { $powerSetting.ToLower() }
            }

            $command = "powercfg.exe /x `"$($powerSettingArgument)-timeout-$($powerModeArgument)`" $powerSettingValue"
            if ($dryrun) {
                Write-Host "[DRY] Would have executed -> $command"
            } else {
                Invoke-Expression $command
            }
        }
    }
}

function main() {
    prepareVariables
    updatePowerSettings
}

main
