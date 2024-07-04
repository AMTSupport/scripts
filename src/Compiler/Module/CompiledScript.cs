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
using QuikGraph.Graphviz;
using Compiler.Analyser;

namespace Compiler;

public partial class CompiledScript : LocalFileModule
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private static readonly string InvokeRunMain = "(New-Module -ScriptBlock ([ScriptBlock]::Create($Global:EmbeddedModules['{0}'].Content)) -AsCustomObject -ArgumentList {1}.BoundParameters).'Invoke-RunMain'({1}, ({2}));";
    [GeneratedRegex(@"(?smi)^Import-Module\s(?:\$PSScriptRoot)?(?:[/\\\.]*(?:(?:src|common)[/\\])+)00-Environment\.psm1;?\s*$", RegexOptions.None, "en-AU")]
    private static partial Regex ImportEnvironmentRegex();
    [GeneratedRegex(@"^Invoke-RunMain\s+(?:\$MyInvocation)?\s+(?<Block>{.+})")]
    private static partial Regex RunMainRegex();

    public readonly BidirectionalGraph<ModuleSpec, Edge<ModuleSpec>> ModuleGraph = new();
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
            var invocation = match.Groups.ContainsKey("Invocation") ? match.Groups["Invocation"].Value : "$MyInvocation";

            Logger.Debug("Invocation: {0}", invocation);
            Logger.Debug("Block: {0}", block);
            Logger.Debug("ResolvedModules: {0}", ResolvedModules.Count);

            return string.Format(InvokeRunMain, ResolvedModules.Find(module => module.PreCompileModuleSpec.Name == "00-Environment")!.ModuleSpec.Name, invocation, block);
        });

        // Extract the param block and its attributes from the script and store it in a variable so we can place it at the top of the script later.
        ScriptParamBlockAst = ExtractParameterBlock();
        ResolveRequirements();
    }

    public string Compile()
    {
        var script = new StringBuilder();

        Requirements.GetRequirements().ToList().ForEach(requirement => script.AppendLine(requirement.GetInsertableLine()));

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

        script.AppendLine("    $Global:CompiledScript = $True;");
        script.AppendLine("    $Global:EmbeddedModules = @{");
        ResolvedModules.ToList().ForEach(module => script.AppendLine(module.ToString()));
        script.AppendLine("};");

        script.AppendLine(/*ps1*/ """
            $Local:PrivatePSModulePath = $env:ProgramData | Join-Path -ChildPath 'AMT/PowerShell/Modules';
            if (-not (Test-Path -Path $Local:PrivatePSModulePath)) {
                Write-Host "Creating module root folder: $Local:PrivatePSModulePath";
                New-Item -Path $Local:PrivatePSModulePath -ItemType Directory | Out-Null;
            }
            if (-not ($Env:PSModulePath -like "*$Local:PrivatePSModulePath*")) {
                $Env:PSModulePath = "$Local:PrivatePSModulePath;" + $Env:PSModulePath;
            }
            $Global:EmbeddedModules.GetEnumerator() | ForEach-Object {
                $Local:Content = $_.Value.Content;
                $Local:Name = $_.Key;
                $Local:ModuleFolderPath = Join-Path -Path $Local:PrivatePSModulePath -ChildPath $Local:Name;
                if (-not (Test-Path -Path $Local:ModuleFolderPath)) {
                    Write-Host "Creating module folder: $Local:ModuleFolderPath";
                    New-Item -Path $Local:ModuleFolderPath -ItemType Directory | Out-Null;
                }
                switch ($_.Value.Type) {
                    'UTF8String' {
                        $Local:InnerModulePath = Join-Path -Path $Local:ModuleFolderPath -ChildPath "$Local:Name.psm1";
                        if (-not (Test-Path -Path $Local:InnerModulePath)) {
                            Write-Host "Writing content to module file: $Local:InnerModulePath"
                            Set-Content -Path $Local:InnerModulePath -Value $Content;
                        }
                    }
                    'ZipHex' {
                        if ((Get-ChildItem -Path $Local:ModuleFolderPath).Count -ne 0) {
                            return;
                        }
                        [String]$Local:TempFile = [System.IO.Path]::GetTempFileName();
                        [Byte[]]$Local:Bytes = [System.Convert]::FromHexString($Content);
                        [System.IO.File]::WriteAllBytes($Local:TempFile, $Local:Bytes);
                        Write-Host "Expanding module file: $Local:TempFile"
                        Expand-Archive -Path $Local:TempFile -DestinationPath $Local:ModuleFolderPath -Force;
                    }
                    Default {
                        Write-Warning "Unknown module type: $($_)";
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
            $Env:PSModulePath = ($Env:PSModulePath -split ';' | Select-Object -Skip 1) -join ';';
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

    // TODO - This is a bit of a mess. Refactor this to be more readable, maybe split it into smaller functions.
    private void ResolveRequirements()
    {
        var (ModuleGraph, unsortedModules) = CreateModuleGraph(this);
        var sortedModules = new Queue<ModuleSpec>(ModuleGraph.TopologicalSort().Reverse()) ?? throw new Exception("Cyclic dependency detected.");
        var graphviz = ModuleGraph.ToGraphviz(alg =>
        {
            alg.FormatVertex += (sender, args) =>
            {
                args.VertexFormat.Label = args.Vertex.Name;
                args.VertexFormat.Comment = args.Vertex.InternalGuid.ToString();
            };
        });
        Logger.Info(message: graphviz);

        ModuleGraph.TopologicalSort().Skip(1).Reverse().ToList().ForEach(moduleSpec =>
        {
            var matchingModule = unsortedModules.Find(module => moduleSpec.CompareTo(module.ModuleSpec) == ModuleMatch.Same) ?? throw new Exception($"Could not find module {moduleSpec.Name} in local or downloadable modules.")!;
            // Update the ModuleSpecs in the resolved modules list to be the actual modules.
            matchingModule.Requirements.GetRequirements<ModuleSpec>().ToList().ForEach(requirement =>
            {
                Logger.Debug("Getting matching module for {0}", requirement.Name);
                var matchingModuleSpec = ResolvedModules.Find(module =>
                {
                    Logger.Debug("Comparing {0} to {1}", module.ModuleSpec.Name, requirement.Name);
                    Logger.Debug("InternalGuid: {0} == {1}", module.ModuleSpec.InternalGuid, requirement.InternalGuid);

                    return module.ModuleSpec.InternalGuid == requirement.InternalGuid;
                })?.ModuleSpec;
                Logger.Debug("Found matching module {0}", matchingModuleSpec?.Name);

                matchingModule.Requirements.RemoveRequirement(requirement);
                matchingModule.Requirements.AddRequirement(matchingModuleSpec ?? throw new Exception($"Could not find module {requirement.Name} in resolved modules."));
            });

            var compiledModule = CompiledModule.From(matchingModule, 8);
            // Only validate unknown requirements for local modules.
            if (matchingModule is LocalFileModule)
            {
                var importedModulesResolved = matchingModule.Requirements.GetRequirements<ModuleSpec>().Select(req => ResolvedModules.Find(module => module.ModuleSpec.InternalGuid == req.InternalGuid));
                StaticAnalyser.Analyse(compiledModule, [.. importedModulesResolved]);
            }
            ResolvedModules.Add(compiledModule);
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

    public static Module.Module? LinkFindingPossibleResolved(
        ModuleSpec? parentModule,
        ModuleSpec currentModule,
        List<Module.Module> unsortedModules,
        ref BidirectionalGraph<ModuleSpec, Edge<ModuleSpec>> moduleGraph
    )
    {
        var alreadyResolvedModule = unsortedModules.Find(module => module.GetModuleMatchFor(currentModule) == ModuleMatch.Same);
        if (alreadyResolvedModule != null)
        {
            if (!moduleGraph.ContainsVertex(alreadyResolvedModule.ModuleSpec))
            {
                Logger.Debug("Adding vertex for {0}", alreadyResolvedModule.Name);
                moduleGraph.AddVertex(alreadyResolvedModule.ModuleSpec);
            }

            Logger.Debug("Skipping {0} because it is already resolved.", currentModule.Name);
            if (parentModule != null)
            {
                moduleGraph.AddEdge(new Edge<ModuleSpec>(parentModule, alreadyResolvedModule.ModuleSpec));
            }

            return alreadyResolvedModule;
        }

        if (!moduleGraph.ContainsVertex(currentModule))
        {
            Logger.Debug("Adding vertex for {0}", currentModule.Name);
            moduleGraph.AddVertex(currentModule);
        }

        if (parentModule != null)
        {
            Logger.Debug("Adding edge from {0} to {1}", parentModule.Name, currentModule.Name);
            moduleGraph.AddEdge(new Edge<ModuleSpec>(parentModule, currentModule));
        }

        return null;
    }

    public static (BidirectionalGraph<ModuleSpec, Edge<ModuleSpec>>, List<Module.Module>) CreateModuleGraph(Module.Module rootModule)
    {
        var moduleGraph = new BidirectionalGraph<ModuleSpec, Edge<ModuleSpec>>();
        var unsortedModules = new HashSet<Module.Module>();

        var iterating = new Queue<(Module.Module?, Module.Module)>([(null, rootModule)]);
        do
        {
            var (parentModule, currentModule) = iterating.Dequeue()!;
            Logger.Debug($"Resolving requirements for {currentModule.Name}");

            // The parent was a module which was already resolved, so we can skip this one as it would be an orphan.
            if (parentModule != null && !moduleGraph.ContainsVertex(parentModule.ModuleSpec))
            {
                Logger.Debug($"Parent to {0} was determined to be already resolved, skipping.", currentModule.Name);
                continue;
            }

            var resolvedModule = LinkFindingPossibleResolved(parentModule?.ModuleSpec, currentModule.ModuleSpec, [.. unsortedModules], ref moduleGraph);
            // The module has already been resolved, so we can skip this one.
            if (resolvedModule != null)
            {
                // Update the modules RequirementGroup to the correct specs.
                if (parentModule != null)
                {
                    Logger.Debug("Updating requirements for parent {0}", parentModule.Name);

                    Logger.Debug("Replacing {0} with {1} in requirements for {2}", currentModule.ModuleSpec.InternalGuid, resolvedModule.ModuleSpec.InternalGuid, parentModule.Name);

                    var replacingReq = parentModule.Requirements.GetRequirements<ModuleSpec>().ToList().Find(req => req.InternalGuid == currentModule.ModuleSpec.InternalGuid)!;
                    parentModule.Requirements.RemoveRequirement(replacingReq);
                    parentModule.Requirements.AddRequirement(resolvedModule.ModuleSpec);
                }

                continue;
            }

            unsortedModules.Add(currentModule);

            currentModule.Requirements.GetRequirements<ModuleSpec>().ToList().ForEach(nestedRequirement =>
            {
                Logger.Debug($"Adding {nestedRequirement.Name} to the queue.");
                Module.Module? requirementModule = null;
                if (currentModule is LocalFileModule local)
                {
                    var parentPath = Path.GetDirectoryName(local.FilePath);
                    requirementModule ??= TryFromFile(parentPath!, nestedRequirement);
                }
                requirementModule ??= new RemoteModule(nestedRequirement);

                iterating.Enqueue((currentModule, requirementModule ?? throw new Exception("Could not resolve module.")));
            });
        } while (iterating.Count > 0);


        return (moduleGraph, [.. unsortedModules]);
    }
}
