#Requires -Version 5.1

Import-Module ../common/Environment.psm1;

Invoke-RunMain $MyInvocation {
    Write-Host "Hello, World!"

    # Sign into EntraID

    # Ensure that the "Travel Access" Group exists, if not create it.
    # Ensure that the "Blocked Countries" Named Location exists, if not create it.
    # Ensure that the "Travel Countries" Named Location exists, if not create it.
    # Ensure that Conditional Access Policy "Travel Access" exists, if not create it.

    # Prompt for selection of users to grant / remove access to.
    # Prompt for which locations are required or were granted.

    # If removing access, remove the "Travel Access" Group from the user.
    # If granting access, add the "Travel Access" Group to the user.

    # If removing access, check the users recent sign-in history and that they are back in australia or office location.
    # If granting access, remove the required countries from the named location "Blocked Countries" and add the required countries to the named location "Travel Countries".
}
