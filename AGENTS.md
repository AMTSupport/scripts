# AGENTS.md

PowerShell modules and C# compiler tools. Modules under `src/`, tests under `tests/`, compiled output in `compiled/`.

## Commands
- **Build**: `dotnet build scripts.sln`
- **Test (C#)**: `dotnet test` (coverage: `--collect:"XPlat Code Coverage"`)
- **Test (PowerShell)**: `Invoke-Pester -Configuration (Import-PowerShellDataFile tests/PesterConfiguration.psd1)`
- **Single test**: `Invoke-Pester tests/common/Assert/Assert-NotNull.Tests.ps1`
- **Lint**: `Invoke-ScriptAnalyzer -Path src -Recurse -Settings PSScriptAnalyzerSettings.psd1`

## Code Style
- **Imports**: Use `Using module .\X.psm1` at file top (not `Import-Module`)
- **Braces**: Open brace on same line (per `PSScriptAnalyzerSettings.psd1`)
- **Scope**: Module config in `Script:` scope (e.g., `$Script:PackageManager`)
- **Logging**: Use `Invoke-Write`, `Invoke-Info`, `Invoke-Warn`, `Invoke-Error`, `Invoke-FailedExit`
- **Flow control**: Use `Enter-Scope`/`Exit-Scope` helpers
- **Exports**: Explicit `Export-ModuleMember` for public functions
- **No globals**: Avoid global state; use existing scope helpers

## Key Patterns
- Defensive checks: network (`Test-NetworkConnection`), idempotency (`Get-Flag`/`Set-Flag`)
- Follow `src/common/PackageManager.psm1` for argument validation and ShouldProcess
- Add tests under `tests/` for behavior changes
- When modifying compiler, update both `src/Compiler` and ensure `compiled/` outputs stay consistent

## Key Files
- `src/common/PackageManager.psm1` — canonical example of module conventions
- `PSScriptAnalyzerSettings.psd1` — linter rules and style settings
- `compiled/` — generated artifacts; understand expected runtime shape

## Search Targets
- `Invoke-Write`, `Enter-Scope`, `Exit-Scope`, `Get-Flag`, `Invoke-FailedExit` — common helpers
- `Using module` — module dependency patterns
