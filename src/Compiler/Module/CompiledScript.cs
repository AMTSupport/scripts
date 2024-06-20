using System.Management.Automation.Language;
using System.Text;
using Compiler.Module;
using Compiler.Requirements;
using Microsoft.CodeAnalysis;
using NLog;
using QuikGraph;
using Compiler.Text;
using System.Text.RegularExpressions;
using QuikGraph.Algorithms;
using CommandLine;

namespace Compiler;

public partial class CompiledScript : LocalFileModule
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private static readonly string InvokeRunMain = "(New-Module -ScriptBlock ([ScriptBlock]::Create($Global:EmbeddedModules['00-Environment'].Content)) -AsCustomObject -ArgumentList {0}.BoundParameters).'Invoke-RunMain'({0}, ({1}));";
    [GeneratedRegex(@"(?smi)^Import-Module\s(?:\$PSScriptRoot)?(?:[/\\\.]*(?:(?:src|common)[/\\])+)00-Environment\.psm1;?\s*$", RegexOptions.None, "en-AU")]
    private static partial Regex ImportEnvironmentRegex();
    [GeneratedRegex(@"^Invoke-RunMain\s+(?:\$MyInvocation)?\s+(?<Block>{.+})")]
    private static partial Regex RunMainRegex();

    public readonly AdjacencyGraph<ModuleSpec, Edge<ModuleSpec>> ModuleGraph = new();
    public readonly List<CompiledModule> ResolvedModules = [];
    public readonly ParamBlockAst? ScriptParamBlockAst;

    public CompiledScript(
        string path
    ) : this(
        path,
        new PathedModuleSpec(path, Path.GetFileNameWithoutExtension(path)),
        new TextDocument(File.ReadAllLines(path))
    )
    { }

    public CompiledScript(
        string path,
        ModuleSpec moduleSpec,
        TextDocument document
    ) : base(path, moduleSpec, document)
    {
        Document.AddRegexEdit(ImportEnvironmentRegex(), match => null);
        Document.AddRegexEdit(RunMainRegex(), UpdateOptions.MatchEntireDocument, match =>
        {
            var block = match.Groups["Block"].Value;
            var invocation = match.Groups["Invocation"].Value;
            if (string.IsNullOrWhiteSpace(invocation))
            {
                invocation = "$MyInvocation";
            }

            return string.Format(InvokeRunMain, invocation, block);
        });

        // Extract the param block and its attributes from the script and store it in a variable so we can place it at the top of the script later.
        ScriptParamBlockAst = ExtractParameterBlock();
        ResolveRequirements();
    }

    public string Compile()
    {
        var script = new StringBuilder();

        Requirements.GetRequirements().Where(requirement => requirement is not Compiler.Requirements.ModuleSpec).ToList().ForEach(requirement =>
        {
            script.AppendLine(requirement.GetInsertableLine());
        });

        if (ScriptParamBlockAst != null)
        {
            ScriptParamBlockAst.Attributes.ToList().ForEach(attribute =>
            {
                script.AppendLine(attribute.Extent.Text);
            });

            script.AppendLine(ScriptParamBlockAst.Extent.Text);
        }

        #region Begin Block
        script.AppendLine("begin {");

        script.AppendLine("    $Global:EmbeddedModules = @{");
        ResolvedModules.ToList().ForEach(module => script.AppendLine(module.ToString()));
        script.AppendLine("};");

        script.AppendLine("""
            $Global:EmbeddedModules | ForEach-Object {
                if ($_.Type -eq 'UTF8String') {
                    $Local:Path = Join-Path $env:TEMP $("($_.Name)-($_.ContentHash).ps1");
                    if (-not (Test-Path $Local:Path)) {
                        Set-Content -Path $Local:Path -Value $_.Content;
                    }
                }
            }
        """);

        script.AppendLine("}");
        #endregion

        #region End Block
        script.AppendLine($$"""
        end {
        {{CompiledDocument.FromBuilder(Document, 4).GetContent()}}
        }
        """);
        #endregion
        return script.ToString();
    }

    public ParamBlockAst? ExtractParameterBlock()
    {
        var scriptParamBlockAst = Ast.ParamBlock;

        if (scriptParamBlockAst == null)
        {
            return null;
        }

        Document.AddExactEdit(
            scriptParamBlockAst.Extent.StartLineNumber - 1,
            scriptParamBlockAst.Extent.StartColumnNumber - 1,
            scriptParamBlockAst.Extent.EndLineNumber - 1,
            scriptParamBlockAst.Extent.EndColumnNumber - 1,
            lines => []
        );

        scriptParamBlockAst.Attributes.ToList().ForEach(attribute =>
        {
            Document.AddExactEdit(
                attribute.Extent.StartLineNumber - 1,
                attribute.Extent.StartColumnNumber - 1,
                attribute.Extent.EndLineNumber - 1,
                attribute.Extent.EndColumnNumber - 1,
                lines => []
            );
        });

        return scriptParamBlockAst;
    }

    private void ResolveRequirements()
    {
        var localModules = new List<LocalFileModule>();
        var downloadableModules = new List<RemoteModule>();

        var iterating = new Queue<Module.Module>([this]);
        while (iterating.TryDequeue(out Module.Module? current) && current != null)
        {
            Logger.Debug($"Resolving requirements for {current.Name}");
            if (localModules.Any(module => module.GetModuleMatchFor(current.ModuleSpec) == ModuleMatch.Same) || downloadableModules.Any(module => module.GetModuleMatchFor(current.ModuleSpec) == ModuleMatch.Same))
            {
                Logger.Debug($"Skipping {current.Name} because it is already resolved.");
                continue;
            }

            switch (current)
            {
                case LocalFileModule local:
                    Logger.Debug($"Adding {local.Name} to local modules.");
                    localModules.Add(local);
                    break;
                case RemoteModule remote:
                    Logger.Debug($"Adding {remote.Name} to downloadable modules.");
                    downloadableModules.Add(remote);
                    break;
            }

            if (!ModuleGraph.ContainsVertex(current.ModuleSpec))
            {
                Logger.Debug($"Adding {current.Name} to module graph.");
                ModuleGraph.AddVertex(current.ModuleSpec);
            }

            current.Requirements.GetRequirements<ModuleSpec>().ForEach(module =>
            {
                Logger.Debug($"Adding {module.Name} to the queue.");

                Module.Module? resolved = null;
                if (current is LocalFileModule local)
                {
                    var parentPath = Path.GetDirectoryName(local.FilePath);
                    Logger.Debug($"Trying to resolve {module.Name} from {parentPath}.");
                    resolved = TryFromFile(parentPath!, module);

                    if (resolved != null)
                    {
                        Logger.Debug($"Resolved {module.Name} from {parentPath}.");
                        ModuleGraph.TryGetOutEdges(module, out var edges);
                        if (edges != null && edges.Any())
                        {
                            Logger.Debug($"Updating graph to use {resolved.Name} instead of {module.Name}.");

                            ModuleGraph.AddVertex(resolved.ModuleSpec);
                            edges.ToList().ForEach(edge =>
                            {
                                ModuleGraph.RemoveEdge(edge);
                                ModuleGraph.AddEdge(new Edge<ModuleSpec>(edge.Source, resolved.ModuleSpec));
                            });
                            ModuleGraph.RemoveVertex(module);
                        }
                    }
                }

                resolved ??= RemoteModule.FromModuleRequirement(module);

                Logger.Debug($"Adding vertex {resolved.ModuleSpec.Name} to module graph.");
                ModuleGraph.AddVertex(resolved.ModuleSpec);
                ModuleGraph.AddEdge(new Edge<ModuleSpec>(current.ModuleSpec, resolved.ModuleSpec));
                iterating.Enqueue(resolved);
            });
        }

        var sortedModules = ModuleGraph.TopologicalSort() ?? throw new Exception("Cyclic dependency detected.");
        sortedModules.ToList().ForEach(moduleSpec =>
        {
            var matchingModule = (localModules.Find(module => moduleSpec.CompareTo(module.ModuleSpec) == ModuleMatch.Same).Cast<Module.Module>() ?? downloadableModules.Find(module => moduleSpec.CompareTo(module.ModuleSpec) == ModuleMatch.Same)) ?? throw new Exception($"Could not find module {moduleSpec.Name} in local or downloadable modules.")!;
            ResolvedModules.Add(CompiledModule.From(matchingModule, 8));
        });

        PSVersionRequirement? highestPSVersion = null;
        foreach (var module in ResolvedModules)
        {
            foreach (var version in module.Requirements.GetRequirements<PSVersionRequirement>())
            {
                if (highestPSVersion == null || version.Version > highestPSVersion.Version)
                {
                    highestPSVersion = version;
                }
            }
        }

        if (highestPSVersion != null)
        {
            Requirements.AddRequirement(highestPSVersion);
        }

        PSEditionRequirement? foundPSEdition = null;
        ResolvedModules.SelectMany(module => module.Requirements.GetRequirements<PSEditionRequirement>())
            .ToList()
            .ForEach(edition =>
            {
                foundPSEdition ??= edition;

                if (edition.Edition != foundPSEdition.Edition)
                {
                    throw new Exception("Multiple PSEditions found in resolved modules.");
                }
            });

        if (foundPSEdition != null)
        {
            Requirements.AddRequirement(foundPSEdition);
        }

        ResolvedModules.SelectMany(module => module.Requirements.GetRequirements<RunAsAdminRequirement>())
            .ToList()
            .ForEach(requirements =>
            {
                if (Requirements.GetRequirements<RunAsAdminRequirement>().Count == 0)
                {
                    Requirements.AddRequirement(requirements);
                }
            });
    }
}
