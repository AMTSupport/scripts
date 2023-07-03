# Registry Automation Scripts

This folder contains scripts that are used to update a Windows registry key. These scripts should be run on a regular basis to ensure that the value of the registry key does not change.

## Creating new scripts

To create new scripts for registry key updates copy one of the templates below, rename it and change the values of the parameters to match the registry key you want to modify.

### Static Value

For registry keys where the value is determinded by the script and does not change, use the [fixed template script](./template_fixed.ps1).

### Dynamic Value

For registry keys where the value is provided by an argument, use the [dynamic template script](./template_dynamic.ps1).
