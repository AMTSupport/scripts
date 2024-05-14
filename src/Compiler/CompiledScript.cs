using System.Management.Automation.Language;
using System.Text;
using Compiler.Module;
using Compiler.Requirements;
using QuikGraph;

class CompiledScript : LocalFileModule
{
    public readonly AdjacencyGraph<ModuleSpec, Edge<ModuleSpec>> ModuleGraph = new();
    public readonly Dictionary<string, Module> ResolvedModules = [];
    public readonly ParamBlockAst ScriptParamBlockAst;

    public CompiledScript(string name, string[] lines) : base(name, lines)
    {

        foreach (var module in Requirements.GetRequirements<ModuleSpec>())
        {
            ModuleGraph.AddEdge(new Edge<ModuleSpec>(ModuleSpec, module));
        }

        // Extract the param block and its attributes from the script and store it in a variable so we can place it at the top of the script later.
        ScriptParamBlockAst = Ast.ParamBlock;
        Document.AddExactEdit(
            ScriptParamBlockAst.Extent.StartLineNumber - 1,
            ScriptParamBlockAst.Extent.StartColumnNumber - 1,
            ScriptParamBlockAst.Extent.EndLineNumber - 1,
            ScriptParamBlockAst.Extent.EndColumnNumber - 1,
            lines => []
        );
        ScriptParamBlockAst.Attributes.ToList().ForEach(attribute =>
        {
            Document.AddExactEdit(
                attribute.Extent.StartLineNumber - 1,
                attribute.Extent.StartColumnNumber - 1,
                attribute.Extent.EndLineNumber - 1,
                attribute.Extent.EndColumnNumber - 1,
                lines => []
            );
        });

        ResolveRequirements();

        // Remove all the using statmenets from the script.
        var usingStatements = Ast.FindAll(ast => ast is UsingStatementAst usingStatment && usingStatment.UsingStatementKind == UsingStatementKind.Module, false).ToList();
        usingStatements.ForEach(usingStatement =>
        {
            Document.AddExactEdit(
                usingStatement.Extent.StartLineNumber - 1,
                usingStatement.Extent.StartColumnNumber - 1,
                usingStatement.Extent.EndLineNumber - 1,
                usingStatement.Extent.EndColumnNumber - 1,
                lines => []
            );
        });
    }

    public string Compile()
    {
        var script = new StringBuilder();

        Requirements.GetRequirements().ForEach(requirement =>
        {
            script.AppendLine(requirement.GetInsertableLine());
        });

        ScriptParamBlockAst.Attributes.ToList().ForEach(attribute =>
        {
            script.AppendLine(attribute.Extent.Text);
        });
        script.AppendLine(ScriptParamBlockAst.Extent.Text);

        script.AppendLine(GetModuleTable());

        script.AppendLine(Document.GetContent());

        return script.ToString();
    }

    private void ResolveRequirements()
    {
        var localModules = new List<LocalFileModule>();
        var downloadableModules = new List<RemoteModule>();

        var iterating = new Queue<Module>([this]);
        while (iterating.TryDequeue(out Module? current) && current != null)
        {
            if (localModules.Any(module => module.GetModuleMatchFor(current.ModuleSpec) == ModuleMatch.Exact) || downloadableModules.Any(module => module.GetModuleMatchFor(current.ModuleSpec) == ModuleMatch.Exact))
            {
                continue;
            }

            switch (current)
            {
                case LocalFileModule local:
                    localModules.Add(local);
                    break;
                case RemoteModule remote:
                    downloadableModules.Add(remote);
                    break;
            }

            if (!ModuleGraph.ContainsVertex(current.ModuleSpec))
            {
                ModuleGraph.AddVertex(current.ModuleSpec);
            }

            ModuleGraph.AddEdge(new Edge<ModuleSpec>(ModuleSpec, current.ModuleSpec));

            current.Requirements.GetRequirements<ModuleSpec>().ForEach(module =>
            {
                Module? resolved = null;
                var resolvedPath = Path.GetFullPath(module.Name);
                if (File.Exists(resolvedPath))
                {
                    resolved = FromFile(module.Name);
                }
                else
                {
                    resolved = RemoteModule.FromModuleRequirement(module);
                }

                ModuleGraph.AddEdge(new Edge<ModuleSpec>(current.ModuleSpec, module));
                iterating.Enqueue(resolved);
            });
        }

        localModules.ForEach(module =>
        {
            ResolvedModules.Add(module.Name, module);
        });

        // foreach (var module in downloadableModules)
        // {
        //     if (!ResolvedModules.TryGetValue(module.Name, out Module? value))
        //     {
        //         ResolvedModules.Add(module.Name, module);
        //         continue;
        //     }

        //     var existingModule = value;
        //     if (existingModule.Version < module.Version)
        //     {
        //         ResolvedModules[module.Name] = module;
        //     }
        // }

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
        ResolvedModules.ToList().ForEach(module => table.AppendLine(module.Value.GetInsertableContent().PadLeft(4)));
        table.AppendLine("};");

        return table.ToString();
    }
}
