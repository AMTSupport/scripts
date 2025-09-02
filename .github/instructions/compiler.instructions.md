---
applyTo: src/Compiler/**, tests/Compiler/**
description: Instructions for working with the C# PowerShell Script Compiler
---


## Compiler Project Instructions (C# PowerShell Script Compiler)

Focus: Maintain/extend the C# compiler that ingests PowerShell scripts, resolves module/requirement graphs, analyses code, and emits self-contained compiled scripts (embedding local modules, rewriting remote modules).

### High-Level Architecture
1. Entry point: `Program.Main` parses CLI args (`Options`), sets up logging (NLog), gathers target `.ps1` files (`GetFilesToCompile`), creates a `ResolvableParent`, and orchestrates asynchronous resolution + compilation.
2. Resolution Phase (`Resolvable*` classes):
   - Builds a dependency DAG of modules (local & remote) using `ModuleSpec` + version constraints.
   - Performs merging (ModuleMatch: Same/Stricter/Looser/MergeRequired/Incompatible) and rewrites edges accordingly.
   - Uses `ResolvableParent.ResolveDepedencyGraph` to breadth-first dequeue requirements; each module implements `ResolveRequirements` then `IntoCompiled`.
3. Compilation Phase (`Compiled*` classes):
   - `CompiledLocalModule` wraps local source (AST, transformed content + requirement insert lines).
   - `CompiledRemoteModule` wraps remote zipped module: rewrites manifest `RequiredModules` to point at hashed embedded names; lazily base64 encodes zip content.
   - `CompiledScript` (root) builds a QuikGraph `BidirectionalGraph<Compiled, Edge<Compiled>>` including all dependencies; renders final template (`ScriptTemplate.ps1`) injecting EMBEDDED_MODULES, PARAM_BLOCK, and removal/import order.
4. Analysis (`Analyser`): Executes rule visitors over each local module AST post graph construction; collects `Issue` objects (errors/warnings) added to global `Program.Errors`.
5. Output: Each original script is emitted (or STDOUT) with CRLF normalization and UTF-8 BOM; optionally interactive overwrite unless `--force`.

### Key Types & Responsibilities
- `ModuleSpec` / `PathedModuleSpec`: Identity + version constraints + hash for a module (local path variant caches SHA256 of file).
- `RequirementGroup`: Maintains typed requirement sets (supports ordering by weight for deterministic insertion; see `Requirement.Weight`).
- `Resolvable*`: Pre-compiled representation (Local / Remote / Script) able to discover requirements (e.g., parsing AST for `Using module`, `#Requires`).
- `Compiled*`: Final immutable (content + requirement hash) representations with consistent `ComputedHash`; remote modules may mutate their archive (manifest rewrite) only inside `CompleteCompileAfterResolution` so content-hash stability assumptions hold during graph hashing.
- `Analyser.Rules`: AST-based static checks (MissingCmdlet, UseOfUndefinedFunction) with suppression attributes (`[Compiler.Analyser.SuppressAnalyser(...)]`).

### Hash & Identity Rules
- `ComputedHash` combines content bytes + requirement hashes + sorted outbound dependency hashes to ensure graph-sensitive reproducibility.
- Any content changes AFTER `Compiled` instantiation must NOT influence behavioral correctness (only allowed in `CompleteCompileAfterResolution` for remote module manifest/zip rewriting which updates internal `UpdatedContentBytes`). Avoid late-stage mutations for local modules (would desync `ComputedHash`).
*- Never* recompute or override `ContentBytes` outside constructor / designated lazy initialization.

### Dependency Graph Rules
- Graph edges: Parent (dependent) -> Target (dependency). OutEdges enumerate dependencies.
- During merging (ModuleMatch.MergeRequired / Stricter / Looser), resolvable instances are replaced and edges rewired; maintain thread-safety via locks around `Graph` and `Requirements` as implemented.
- Circular dependencies: Build loop detection throws after no-progress iteration (see `Compile()` batch logic). When adding new resolution logic, ensure it still eventually yields leaf nodes for compilation.

### Requirements Insertion (Local Modules)
- Local compiled output prepends requirement lines inside `<#ps1#> '@'` … `'@;` region; each requirement obtains a 6-char hash suffix (module sibling hash for ModuleSpec else requirement hash) appended via `NameSuffix` hashtable data.
- Order: Determined by `RequirementGroup.GetRequirements()` (weight ascending). Add new requirements with sensible `Weight` to preserve deterministic ordering.

### Remote Module Rewriting
- Manifest parsing: `CompiledRemoteModule.GetPowerShellManifest()` executes raw psd1 inside isolated PowerShell session (errors downgrade to empty hashtable, not fatal).
- `RewriteRequiredModules` maps `RequiredModules` to hashed embedded module names (using `GetNameHash()` of compiled dependencies) and re-serializes using `ObjectGraphTools` (installed on-demand, guarded by lock `RunningExportLock`). Keep this side-effect idempotent.
- `MoveModuleManifest` renames `<Name>.psd1` to `<Name>-<hash>.psd1` (aligns with hashed import names).

### Analysis Framework
- Add a rule: derive from `Rule`, implement `SupportsModule<T>`, `ShouldProcess`, and `Analyse` returning `Issue` objects.
- Use `RuleVisitor` which caches per-thread rule support to minimize per-node overhead.
- Provide suppression via parameter block attributes resolved by `SuppressAnalyserAttributeExt` (see tests when adding new suppression semantics).

### Error & Issue Handling
- All diagnostics accumulate in `Program.Errors` (a `ConcurrentBag<Error>`). Use `ErrorUtils.Enrich(moduleSpec)` to attach module context.
- For AST parse errors: wrap with `WrappedErrorWithDebuggableContent` carrying original content to optionally dump debuggable artifacts (`OutputErrors` writes failing modules when debugging).

### Logging & Verbosity
- Verbosity/quiet flags compute final `LogLevel` ordinal; DEBUG/TRACE add thread IDs and call sites. Keep new logs at appropriate levels to not overwhelm default INFO output.

### Extending / Adding Features (DOs & DON'Ts)
DO:
- Use existing `Fin<T>` / `Option<T>` monadic patterns (`IsErr(out error, out value)`) for error flows instead of exceptions where possible.
- Keep asynchronous graph operations non-blocking; prefer `Task.Run` batches like existing compile/resolution loops.
- Update or add tests under `tests/Compiler` when adding new rules or requirement types.
- Respect thread-safety: mutate shared graphs only within existing locked sections.

DON'T:
- Mutate a `Compiled` instance's `ContentBytes` after hash consumption except via allowed remote rewrite hook.
- Introduce global static state for per-run data (use `ResolvableParent` / graph context).
- Block on long PowerShell invocations without at least capturing and logging streams similar to `RunPowerShell`.

### Adding A New Requirement Type
1. Create subclass of `Requirement` with appropriate `Hash` (stable) and `Weight`.
2. Implement `GetInsertableLine` producing valid PowerShell (e.g., `Using module` or `#Requires -RunAsAdministrator`).
3. Inject detection into relevant `ResolveRequirements` method for local modules / scripts.
4. Ensure compatibility logic if interaction with similar requirements is needed (override `IsCompatibleWith`).

### Adding A New Analyser Rule (Example Skeleton)
```csharp
public sealed class MyRule : Rule {
	public override bool SupportsModule<T>(T compiledModule) => compiledModule is CompiledLocalModule;
	public override bool ShouldProcess(Ast node, IEnumerable<Suppression> suppressions) => /* filter */;
	public override IEnumerable<Issue> Analyse(Ast node, IEnumerable<Compiled> imports) {
		if (/* condition */) yield return Issue.Warning("Something", node.Extent, AstHelper.FindRoot(node));
	}
}
```
Register inside `Analyser.cs` Rules list.

### Testing Guidance (implicit)
- Prefer deterministic input: avoid relying on system module presence (mock or limit function discovery) when testing `UseOfUndefinedFunction` behaviours.
- For graph merging scenarios, craft multiple `Using module` lines with conflicting version ranges to assert `ModuleMatch` behaviour.

### Performance Considerations
- Rule execution: Only traverse AST once per module (`RuleVisitor`), so new rules should be lightweight per node.
- Hash computation: Avoid re-reading large files; `PathedModuleSpec` caches hash after first read in `LazyHash`.
- Parallelism: Resolution enqueues tasks; be cautious adding synchronous waits inside those tasks.

### When in Doubt
- Trace with `-vv` (two -v flags) for DEBUG detail; `-vvv` enables TRACE.
- Add temporary TRACE logs (remove before committing) rather than modifying hashing/content flows.

### Non-Obvious Behaviours
- Local module version fixed to 0.0.1; uniqueness comes from `ComputedHash` not semantic versioning.
- Graph Topological sort is reversed to ensure dependencies are added before dependents within script template embedding.
- `$Script:EMBEDDED_MODULES` includes root script object first; removal order stored in `$Script:REMOVE_ORDER` (reverse topological excluding root).

### Safe Points for Extension
- New rule types (pure read-only) — low risk.
- New requirement types (ensure weight & hash stable) — medium risk.
- Additional logging or error enrichment — low risk.
- Graph algorithm changes (resolution / merging logic) — high risk; require tests and manual validation.

