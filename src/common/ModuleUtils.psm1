<#
.SYNOPSIS
    Exports the types from a module for importing.

.DESCRIPTION
    This function will export the types from a module for importing.
    These types will be added to the TypeAccelerators class which will allow them to be used in other modules after importing.

.EXAMPLE
    Export the some types from the module.
    ```
    Export-Types -Types (
        [System.Management.Automation.PSCredential],
        [System.Management.Automation.PSObject],
        [System.Management.Automation.PSModuleInfo]
    );
    ```

.PARAMETER Types
    The types to export from the module.

.PARAMETER Clobber
    If the types should be allowed to clobber existing type accelerators.

.INPUTS
    None

.OUTPUTS
    None

.FUNCTIONALITY
    Module Management
    Type Accelerators

.EXTERNALHELP
    https://amtsupport.github.io/scripts/docs/modules/Utils/Export-Types
#>
function Export-Types {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Type[]]$Types,

        [Switch]$Clobber,

        [Parameter(DontShow)]
        [PSModuleInfo]$Module = (Get-PSCallStack)[0].InvocationInfo.MyCommand.ScriptBlock.Module
    )

    if (-not $Module) {
        throw [System.InvalidOperationException]::new('This function must be called from within a module.');
    }

    # Get the internal TypeAccelerators class to use its static methods.
    $TypeAcceleratorsClass = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators');

    if (-not $Clobber) {
        # Ensure none of the types would clobber an existing type accelerator.
        # If a type accelerator with the same name exists, throw an exception.
        $ExistingTypeAccelerators = $TypeAcceleratorsClass::Get;
        foreach ($Type in $Types) {
            if ($Type.FullName -in $ExistingTypeAccelerators.Keys) {
                $Message = @(
                    "Unable to register type accelerator '$($Type.FullName)'"
                    'Accelerator already exists.'
                ) -join ' - '

                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new($Message),
                    'TypeAcceleratorAlreadyExists',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $Type.FullName
                )
            }
        }
    }

    # Add type accelerators for every exportable type.
    foreach ($Type in $Types) {
        $TypeAcceleratorsClass::Add($Type.FullName, $Type);
    }

    # Remove type accelerators when the module is removed.
    Add-ModuleCallback -Module $Module -ScriptBlock {
        foreach ($Type in $Types) {
            $null = $TypeAcceleratorsClass::Remove($Type.FullName);
        }
    }.GetNewClosure();
}

<#
.SYNOPSIS
    Adds a function to be executed when the module is removed.

.DESCRIPTION
    This function will add a function to be executed when the module is removed.
    This is useful for cleaning up resources when the module is removed.

.EXAMPLE
    Add a function to be executed when the module is removed.
    ```
    $TempFile = [System.IO.Path]::GetTempFileName();
    # Do something with the temp file.

    Add-OnRemove {
        Remove-Item -Path $TempFile -Force;
    }
    ```

.PARAMETER ScriptBlock
    The script block to execute when the module is removed.

.PARAMETER Module
    The module to add the callback to. Defaults to the current module.

.INPUTS
    None

.OUTPUTS
    None

.FUNCTIONALITY
    Module Management

.EXTERNALHELP
    https://amtsupport.github.io/scripts/docs/modules/Utils/Add-ModuleCallback
#>
function Add-ModuleCallback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $ScriptBlock,

        [Parameter()]
        $Module = (Get-PSCallStack)[0].InvocationInfo.MyCommand.ScriptBlock.Module
    )

    if (-not $Module) {
        throw [System.InvalidOperationException]::new('This function must be called from within a module.');
    }

    if ($Module.OnRemove) {
        $PreviousScriptBlock = $Module.OnRemove;
        $Module.OnRemove = {
            & $PreviousScriptBlock;
            & $ScriptBlock;
        }.GetNewClosure();
        return;
    } else {
        $Module.OnRemove = $ScriptBlock;
    }
}

Export-ModuleMember -Function Export-Types, Add-ModuleCallback;
