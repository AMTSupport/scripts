## Quick orientation

This repository is a curated collection of PowerShell and compiled helper tools maintained under `src/` and shipped to `compiled/`.
Key directories: `src/` (source modules and helper code), `compiled/` (published/transformed scripts), `tests/` (test scripts), and `utils/`.

Workload summary for an AI code agent:
- Primary language: PowerShell modules (.psm1) and a small C# compiler under `src/Compiler` used to build/compile scripts.
- Modules follow an internal conventions set: local helper modules (e.g. `Logging.psm1`, `Scope.psm1`) are `Using`-imported at the top of each module.
- Modules rely on project-level utilities like `Enter-Scope` / `Exit-Scope`, `Invoke-Write` / `Invoke-Info` / `Invoke-Error` for consistent logging and flow-control.

## What to look for first (important files)
- `README.md` — high-level repo overview and one-liner usage patterns.
- `scripts.sln` — solution used for building compiled tooling and tests.
- `src/common/PackageManager.psm1` — example of module conventions: `Using module .\Logging.psm1`, `Script:` scope variables, and defensive patterns around environment and network checks.
- `PSScriptAnalyzerSettings.psd1` — repository's linter rules and style hints (follow `PSPlaceOpenBrace` settings etc.).
- `compiled/` — generated artifacts; useful for understanding expected runtime shape of modules.

## Architecture & patterns (big picture)
- Modules are written as self-contained PowerShell modules that `Using module` the small local helper modules. Expect functions to call into shared helpers rather than embedding logging or scope management inline.
- Shared state uses `Script:` scope variables for per-module configuration (e.g. `$Script:PackageManager`) and explicit exported functions via `Export-ModuleMember`.
- The repository uses a C#-based Compiler component under `src/Compiler` to produce or assist with compiled outputs; read both the C# project and the produced `compiled/` outputs together to understand transformations.

## Developer workflows (commands you can run)
- Build the solution (recommended):

```powershell
dotnet build "${PWD}\scripts.sln"
```

- Run the project in watch mode (useful when iterating on the compiler):

```powershell
dotnet watch run --project "${PWD}\scripts.sln"
```

- Run tests and collect coverage (matches the repo tasks):

```powershell
dotnet test --collect:"XPlat Code Coverage" /p:CollectCoverage=true /p:CoverletOutput=Coverage/ /p:CoverletOutputFormat=lcov
```

- VS Code tasks that exist in the workspace (use these labels if running tasks): `build`, `publish`, `watch`, `Generate coverage stats`, `Generate coverage report`.

## Project-specific conventions and gotchas (do not break these)
- Prefer `Using module .\X.psm1` at the top of modules instead of `Import-Module` to ensure compile-time binding.
- Logging and flow-control: use `Invoke-Write`, `Invoke-Info`, `Invoke-Warn`, `Invoke-Error`, and `Invoke-FailedExit` rather than writing ad-hoc `Write-Host` or `throw`.
- Scope usage:
  - Module-level configuration commonly lives in `Script:` scope (e.g. `$Script:PackageManager`, `$Script:PackageManagerDetails`).
  - Avoid introducing global state unless intentionally required — prefer existing `Enter-Scope` / `Exit-Scope` helpers.
- Linter rules are controlled in `PSScriptAnalyzerSettings.psd1`. Follow those settings (e.g. brace placement) to avoid noisy PR comments.
- When touching environment bootstrap or tools (Chocolatey install, etc.), keep defensive checks similar to `Install-Requirement` in `src/common/PackageManager.psm1` (network checks, idempotency flags via `Get-Flag`/`Set-Flag`).

## Integration and external dependencies
- Chocolatey is the primary package manager target on Windows. Modules detect it and call the choco executable under `%ProgramData%`.
- Some flows call out to the network (download installers or Chocolatey install script) — include network availability checks like `Test-NetworkConnection` before such operations.

## How an AI agent should modify code (rules of engagement)
- Preserve existing module imports and exported function names. Add helpers to `src/common` when multiple modules will reuse them.
- Keep `Script:` scope configuration where present. If a change requires cross-module shared defaults (for example: `$PSDefaultParameterValues`), do not change variables in module scope; instead document the required global change and prefer adding a bootstrap step executed from the user's profile or a documented `init` script.
- When modifying compile-time behavior, update both `src/Compiler` and `compiled/` (or add a task that generates the compiled artifact) so user-visible outputs remain consistent.

## Quick code navigation hints (search targets)n
- Search for: `Invoke-Write`, `Enter-Scope`, `Exit-Scope`, `Get-Flag`, `Invoke-FailedExit` to find common helpers.
- Search for `Using module` to find module dependency patterns and ordering.

## Examples to copy when generating code
- Follow `Install-ManagedPackage` pattern in `src/common/PackageManager.psm1` for argument validation, ShouldProcess support, and logging.
- Follow PSScriptAnalyzer settings in `PSScriptAnalyzerSettings.psd1` to keep formatting consistent.

## Final notes
- Keep changes small, add tests under `tests/` for behavior fixes, and run the `build` and `Generate coverage stats` tasks to validate.
- If something is ambiguous (e.g., cross-module default configuration), open a PR that documents the proposed runtime change and shows a minimal bootstrap script (don't silently change global state).

Please review this file for missing examples or unclear areas and tell me which parts you'd like expanded (build/test examples, more file-level references, or examples of common helper functions).
