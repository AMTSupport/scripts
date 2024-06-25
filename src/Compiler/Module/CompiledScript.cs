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
    private static readonly string InvokeRunMain = "(New-Module -ScriptBlock ([ScriptBlock]::Create($Global:EmbeddedModules['{0}'].Content)) -AsCustomObject -ArgumentList {1}.BoundParameters).'Invoke-RunMain'({1}, ({2}));";
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

            return string.Format(InvokeRunMain, ResolvedModules.Find(module =>
            {
                return module.PreCompileModuleSpec.Name == "00-Environment";
            })!.ModuleSpec.Name, invocation, block);
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
                $Local:NameHash = $_.Key;
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
                        if (Test-Path -Path $Local:ModuleFolderPath) {
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

        ModuleGraph.RemoveVertex(ModuleSpec); // Remove the script from the graph so it doesn't try to resolve itself.
        var sortedModules = new Queue<ModuleSpec>(ModuleGraph.TopologicalSort()) ?? throw new Exception("Cyclic dependency detected.");
        while (sortedModules.TryDequeue(out var moduleSpec))
        {
            Logger.Debug("Sorting module: {0}", moduleSpec.Name);

            var module = localModules.Find(module => moduleSpec.CompareTo(module.ModuleSpec) == ModuleMatch.Same).Cast<Module.Module>()
                ?? downloadableModules.Find(module => moduleSpec.CompareTo(module.ModuleSpec) == ModuleMatch.Same)
                ?? throw new Exception($"Could not find module {moduleSpec.Name} in local or downloadable modules.");
            Logger.Debug("Found matching module {0}", module.Name);

            Logger.Debug("Trying to update module requirements for {0}", module.Name);

            module.Requirements.GetRequirements<ModuleSpec>().ForEach(moduleSpec =>
            {
                Logger.Debug("Getting matching module for {0}", moduleSpec.Name);

                var matchingModule = ResolvedModules.Find(module =>
                {
                    Logger.Debug("Comparing {0} to {1}", module.ModuleSpec.Name, moduleSpec.Name);
                    Logger.Debug("InternalGuid: {0} == {1}", module.ModuleSpec.InternalGuid, moduleSpec.InternalGuid);

                    return module.ModuleSpec.InternalGuid == moduleSpec.InternalGuid;
                }) ?? throw new Exception($"Could not find module {moduleSpec.Name} in resolved modules.")!;
                Logger.Debug("Found matching module {0}", matchingModule.ModuleSpec.Name);

                module.Requirements.RemoveRequirement(moduleSpec);
                module.Requirements.AddRequirement(matchingModule.ModuleSpec);
            });
        }

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
