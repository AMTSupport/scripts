# AGENTS.md

PowerShell modules and C# compiler tools. Modules under `src/`, tests under `tests/`, compiled output in `compiled/`.

## Commands
- **Build**: `dotnet build scripts.sln`
- **Test (C#)**: `dotnet test` (coverage: `--collect:"XPlat Code Coverage"`)
- **Test (PowerShell)**: `Invoke-Pester -Configuration (Import-PowerShellDataFile tests/PesterConfiguration.psd1)`
- **Single test**: `Invoke-Pester tests/microsoft/windows/DriverLock.Tests.ps1`
- **Lint**: `Invoke-ScriptAnalyzer -Path src -Recurse -Settings PSScriptAnalyzerSettings.psd1`

## Code Style
- **Imports**: Use `Using module <relative>/Output/PowerShellModules/AMT.PowerShell.Common/AMT.PowerShell.Common.psd1` at file top (not `Import-Module`)
- **Braces**: Open brace on same line (per `PSScriptAnalyzerSettings.psd1`)
- **Scope**: Module config in `Script:` scope (e.g., `$Script:PackageManager`)
- **Logging**: Use `Invoke-Write`, `Invoke-Info`, `Invoke-Warn`, `Invoke-Error`, `Invoke-FailedExit`
- **Flow control**: Use `Enter-Scope`/`Exit-Scope` helpers
- **Exports**: List cmdlets in `src/AMT.PowerShell.Common/Module/AMT.PowerShell.Common.psd1` `CmdletsToExport`
- **No globals**: Avoid global state; use existing scope helpers

## Key Patterns
- Defensive checks: network (`Test-NetworkConnection`), idempotency (`Get-Flag`/`Set-Flag`)
- Follow `src/AMT.PowerShell.Common/Commands/PackageManager/InstallManagedPackageCommand.cs` for argument validation and ShouldProcess
- Add tests under `tests/` for behavior changes
- When modifying compiler, update both `src/Compiler` and ensure `compiled/` outputs stay consistent

## Key Files
- `src/AMT.PowerShell.Common/Module/AMT.PowerShell.Common.psd1` — module export surface
- `src/AMT.PowerShell.Common/Commands/PackageManager/` — canonical cmdlet/service pattern
- `PSScriptAnalyzerSettings.psd1` — linter rules and style settings
- `compiled/` — generated artifacts; understand expected runtime shape

## Search Targets
- `Invoke-Write`, `Enter-Scope`, `Exit-Scope`, `Get-Flag`, `Invoke-FailedExit` — common helpers
- `Using module` — module dependency patterns
