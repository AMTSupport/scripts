---
name: powershell-modules
description: Writing PowerShell scripts for tasks and automations.
---

## When to use me

Use this when working on PowerShell code.

## Module Structure

### Imports
Use `Using module .\X.psm1` at file top (compile-time binding), NOT `Import-Module`.

### Logging
Use `Invoke-{Info,Warn,Error,Verbose,Debug}` instead of PowerShell `Write` Cmdlets.

### Common Modules
- `Logging.psm1` — `Invoke-Write`, `Invoke-Info`, `Invoke-Warn`, `Invoke-Error`, `Invoke-Debug`, `Invoke-Verbose`
- `Scope.psm1` — `Enter-Scope`, `Exit-Scope` (flow control)
- `Exit.psm1` — `Invoke-FailedExit` (controlled exits)
- `Utils.psm1` — `Test-NetworkConnection`, general utilities
- `Flag.psm1` — `Get-Flag`, `Set-Flag` (idempotency)

### Function Template
```powershell
function Verb-Noun {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Name
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Result; }

    process {
        @{
            PSPrefix  = '📦';
            PSMessage = "Doing something with '$Name'...";
            PSColour  = 'Green';
        } | Invoke-Write;

        # Implementation
    }
}
```

### Scope Variables
- Use `Script:` scope for module-level config: `$Script:ConfigValue`
- Use `Local:` scope for function-local variables: `$Local:Result`
- Never use global scope

### Exports
Always explicit: `Export-ModuleMember -Function Verb-Noun, Verb-Other;`

### Error Handling
```powershell
try {
    # risky operation
} catch {
    Invoke-Error "Description of what failed";
    Invoke-Error $_.Exception.Message;
    Invoke-FailedExit -ExitCode $LASTEXITCODE -DontExit:$NoFail;
}
```

### Defensive Patterns
```powershell
# Network check before downloads
if (-not (Test-NetworkConnection)) {
    Invoke-Error 'No network connection detected.';
    Invoke-FailedExit -ExitCode 9999;
}

# Idempotency with flags
if (Get-Flag -Name 'TaskCompleted') {
    Invoke-Debug 'Already completed. Skipping...';
    return;
}
# ... do work ...
Set-Flag -Name 'TaskCompleted';
```

### Brace Style
Open brace on same line (per PSScriptAnalyzerSettings.psd1):
```powershell
if ($condition) {
    # code
} else {
    # code
}
```

### Testing
Add tests under `tests/` mirroring the source structure:
- `src/common/Assert.psm1` → `tests/common/Assert/Assert-NotNull.Tests.ps1`
- Run single test: `Invoke-Pester tests/common/Assert/Assert-NotNull.Tests.ps1`

## Commands
- **Lint**: `Invoke-ScriptAnalyzer -Path src -Recurse -Settings PSScriptAnalyzerSettings.psd1`
- **Test**: `Invoke-Pester -Configuration (Import-PowerShellDataFile tests/PesterConfiguration.psd1)`

## Reference Files
- `src/common/PackageManager.psm1` — canonical module example
- `PSScriptAnalyzerSettings.psd1` — linter rules
