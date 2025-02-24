# Registry Change Scripts

Provides a way to generate registry change scripts based on simple definitions.
Using the [json schema](../../../resources/schemas/RegistryDefinition.schema.jsonc) to define the registry changes, the scripts can be generated to apply the changes.

---

## Definitions

A simple definition may look like this:

```jsonc
{
    "$schema": "../../../../resources/schemas/RegistryDefinition.schema.jsonc",
    "entries": [
        {
            "key": "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System",
            "values": [
                {
                    "name": "EnableLUA",
                    "type": "REG_DWORD",
                    "data": 0
                }
            ]
        }
    ]
}
```

This definition will generate a script that will set the `EnableLUA` value to `0` in the `HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System` key.

You can declare multiple registry changes in a single definition by adding more entries to the `entries` array:

```jsonc
{
    "$schema": "../../../../resources/schemas/RegistryDefinition.schema.jsonc",
    "entries": [
        {
            "key": "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System",
            "values": [
                {
                    "name": "EnableLUA",
                    "type": "REG_DWORD",
                    "data": 0
                }
            ]
        },
        {
            "key": "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System",
            "values": [
                {
                    "name": "ConsentPromptBehaviorAdmin",
                    "type": "REG_DWORD",
                    "data": 0
                }
            ]
        }
    ]
}
```

---

## Generation

To generate the scripts from the definitions, the [Generate.ps1](./Generate.ps1) script is used.
This script will read the definitions from the [definitions](./definitions/) folder and generate the scripts in the [generated](./generated/) folder.
The script itself has no parameters and has the definitions and output folder based on where the script is located.

---

## Structure

- [definitions](./definitions/): Contains the descriptions used to generate the registry change scripts.
- [generated](./generated/): The output folder where the generated registry change scripts are stored.

---

## Usage

1. Add or update descriptions in the [definitions](./definitions/) folder.
2. Run the script generation tool to create the registry change scripts based on the templates and descriptions.
    - This will be run automatically by the CI/CD pipeline if pushed to the master branch.
3. The generated scripts will be available in the [generated](./generated/) folder.
