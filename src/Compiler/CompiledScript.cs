using System.Management.Automation.Language;
using System.Text;
using Compiler.Module;
using Compiler.Requirements;
using Microsoft.CodeAnalysis;
using NLog;
using QuikGraph;
using Compiler.Text;
using System.Text.RegularExpressions;

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
    public readonly Dictionary<string, Module.Module> ResolvedModules = [];
    public readonly ParamBlockAst? ScriptParamBlockAst;

    public CompiledScript(
        string path
    ) : this(
        path,
        new ModuleSpec(Path.GetFileNameWithoutExtension(path)),
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

        script.AppendLine(GetModuleTable());

        var compiled = CompiledDocument.FromBuilder(Document);
        script.AppendLine(compiled.GetContent());

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
                    resolved = TryFromFile(parentPath, module.Name);
                }

                resolved ??= RemoteModule.FromModuleRequirement(module);

                ModuleGraph.AddVertex(module);
                ModuleGraph.AddEdge(new Edge<ModuleSpec>(current.ModuleSpec, module));
                iterating.Enqueue(resolved);
            });
        }

        localModules.FindAll(module => module != this).ForEach(module => ResolvedModules.Add(module.Name, module));
        downloadableModules.ForEach(module => ResolvedModules.Add(module.Name, module));

        PSVersionRequirement? highestPSVersion = null;
        foreach (var module in ResolvedModules.Values)
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
        ResolvedModules.Values.SelectMany(module => module.Requirements.GetRequirements<PSEditionRequirement>())
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

        ResolvedModules.Values.SelectMany(module => module.Requirements.GetRequirements<RunAsAdminRequirement>())
            .ToList()
            .ForEach(requirements =>
            {
                if (Requirements.GetRequirements<RunAsAdminRequirement>().Count == 0)
                {
                    Requirements.AddRequirement(requirements);
                }
            });
    }

    private string GetModuleTable()
    {
        var table = new StringBuilder();
        table.AppendLine("$Global:EmbeddedModules = @{");
        ResolvedModules.ToList().ForEach(module => table.AppendLine(module.Value.GetInsertableContent(4)));
        table.AppendLine("};");

        return table.ToString();
    }
}
