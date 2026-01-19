---
name: compiler
description: .NET Compiler for PowerShell code, combines all required files from imports into a single output with post-processors.
---

## When to use me

Use this when working with files under `src/Compiler/` or `tests/Compiler/` or asked questions about compiled scripts.

## Overview
C# project that compiles PowerShell scripts into self-contained executables. Resolves module dependencies, performs AST analysis, and embeds local/remote modules.

## Architecture

### Entry Point
`Program.Main` → CLI parsing → file gathering → `ResolvableParent` orchestration → async compilation

### Key Phases
1. **File Gathering**: Collect `.ps1` files, skip `#!ignore` headers
2. **Parsing**: Build PowerShell AST via `System.Management.Automation.Language`
3. **Resolution**: Discover dependencies via `Using module` statements, `#Requires`
4. **AST Transformation**: Rewrite paths, add metadata, minimize output
5. **Analysis**: Run rule visitors, collect `Issue` objects
6. **Output**: Emit CRLF-normalized UTF-8 BOM files

### Key Types
| Type | Purpose |
|------|---------|
| `ModuleSpec` / `PathedModuleSpec` | Module identity + version + hash |
| `RequirementGroup` | Typed requirement sets with ordering |
| `Resolvable*` | Pre-compiled (Local/Remote/Script) |
| `Compiled*` | Final immutable representations |
| `Rule` / `RuleVisitor` | AST-based static analysis |

## Code Patterns

### Error Handling
Use `Fin<T>` / `Option<T>` monadic patterns:
```csharp
if (maybeValue.IsErr(out var error, out var value)) {
    Errors.Add(error);
    return;
}
```

### Hash Stability
- `ComputedHash` combines content + requirements + dependency hashes
- Never mutate `ContentBytes` after hash consumption
- Exception: `CompleteCompileAfterResolution` for remote manifest rewrite

### Thread Safety
- Mutate graphs only within locked sections
- Use `ConcurrentBag<Error>` for diagnostics
- Prefer `Task.Run` batches for parallelism

## Adding Features

### New Requirement Type
1. Subclass `Requirement` with stable `Hash` and `Weight`
2. Implement `GetInsertableLine()` for PowerShell output
3. Add detection in `ResolveRequirements`
4. Override `IsCompatibleWith` if needed

### New Analyser Rule
```csharp
public sealed class MyRule : Rule {
    public override bool SupportsModule<T>(T mod) => mod is CompiledLocalModule;
    public override bool ShouldProcess(Ast node, IEnumerable<Suppression> suppressions)
        => /* filter */;
    public override IEnumerable<Issue> Analyse(Ast node, IEnumerable<Compiled> imports) {
        if (/* condition */)
            yield return Issue.Warning("Message", node.Extent, AstHelper.FindRoot(node));
    }
}
```
Register in `Analyser.cs` Rules list.

## Commands
- **Build**: `dotnet build scripts.sln`
- **Test**: `dotnet test`
- **Single test**: `dotnet test --filter "FullyQualifiedName~TestName"`
- **Debug**: Run with `-vv` (DEBUG) or `-vvv` (TRACE)

## Risk Levels
| Change Type | Risk |
|-------------|------|
| New rule (read-only) | Low |
| New requirement type | Medium |
| Graph algorithm changes | High — requires tests |

## Key Files
- `Program.cs` — entry point, CLI, output
- `Module/Resolvable/*.cs` — dependency resolution
- `Module/Compiled/*.cs` — final representations
- `Analyser/Rules/*.cs` — static analysis rules
- `Resources/ScriptTemplate.ps1` — output template

## Non-Obvious Behaviors
- Local module versions fixed to `0.0.1`; uniqueness via `ComputedHash`
- Graph topological sort is reversed for embedding order
- `$Script:EMBEDDED_MODULES` includes root script first
- `$Script:REMOVE_ORDER` is reverse topological excluding root
