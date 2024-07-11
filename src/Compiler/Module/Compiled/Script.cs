using System.Collections;
using System.Management.Automation.Language;
using System.Text;
using Compiler.Analyser;
using Compiler.Module.Resolvable;
using Compiler.Requirements;
using Compiler.Text;
using NLog;
using QuikGraph;
using QuikGraph.Algorithms;
using QuikGraph.Graphviz;

namespace Compiler.Module.Compiled;

public class CompiledScript : Compiled
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public readonly ParamBlockAst? ScriptParamBlock;

    public readonly BidirectionalGraph<Compiled, Edge<Compiled>> Graph;

    public readonly CompiledDocument Document;

    public override string ComputedHash => throw new NotImplementedException();

    public override ContentType ContentType => throw new NotImplementedException();

    public override Version Version => throw new NotImplementedException();

    public CompiledScript(
        PathedModuleSpec moduleSpec,
        TextEditor editor,
        ResolvableParent resolvableParent,
        ParamBlockAst? scriptParamBlock
    ) : base(moduleSpec)
    {
        var graphviz = resolvableParent.Graph.ToGraphviz(alg =>
        {
            alg.FormatVertex += (sender, args) =>
            {
                args.VertexFormat.Label = args.Vertex.ModuleSpec.Name;
                args.VertexFormat.Comment = args.Vertex.ModuleSpec.InternalGuid.ToString();
            };
        });
        Logger.Debug("Initial graphviz:");
        Logger.Debug(graphviz);

        Document = CompiledDocument.FromBuilder(editor, 0);
        ScriptParamBlock = scriptParamBlock;
        Graph = new BidirectionalGraph<Compiled, Edge<Compiled>>();
        Graph.AddVertex(this);

        Graph.VertexAdded += vertex => Logger.Debug($"Vertex added: {vertex.ModuleSpec.Name}");
        Graph.VertexRemoved += vertex => Logger.Debug($"Vertex removed: {vertex.ModuleSpec.Name}");
        Graph.EdgeAdded += edge => Logger.Debug($"Edge added: {edge.Source.ModuleSpec.Name} -> {edge.Target.ModuleSpec.Name}");
        Graph.EdgeRemoved += edge => Logger.Debug($"Edge removed: {edge.Source.ModuleSpec.Name} -> {edge.Target.ModuleSpec.Name}");

        var loadOrder = resolvableParent.Graph.TopologicalSort();
        var reversedLoadOrder = loadOrder.Reverse();
        reversedLoadOrder.ToList().ForEach(resolvable =>
        {
            Logger.Trace($"Compiling {resolvable.ModuleSpec.Name}");

            var compiledRequirements = resolvableParent.Graph
                .OutEdges(resolvable)
                .AsParallel()
                .Select(edge =>
                {
                    try
                    {
                        Logger.Trace($"Getting compiled module for {edge.Target.ModuleSpec}");
                        return Graph.Vertices.First(module => module.ModuleSpec == edge.Target.ModuleSpec);
                    }
                    catch
                    {
                        Logger.Trace($"Could not find module from edge {edge.Target.ModuleSpec}");
                        throw;
                    }
                });

            Compiled compiledModule;
            if (resolvable.ModuleSpec == moduleSpec) { compiledModule = this; }
            else { compiledModule = resolvable.IntoCompiled(); }

            if (compiledRequirements.Any()) { Graph.AddVerticesAndEdgeRange(compiledRequirements.Select(requirement => new Edge<Compiled>(compiledModule, requirement))); }
            else { Graph.AddVertex(compiledModule); }
        });

        graphviz = Graph.ToGraphviz(alg =>
        {
            alg.FormatVertex += (sender, args) =>
            {
                args.VertexFormat.Label = args.Vertex.ModuleSpec.Name;
                args.VertexFormat.Comment = args.Vertex.ModuleSpec.InternalGuid.ToString();
            };
        });
        Logger.Debug("Compiled graphviz:");
        Logger.Debug(graphviz);

        Logger.Trace("Analyzing compiled modules.");
        Graph.Vertices.Where(compiled => compiled is CompiledLocalModule).ToList().ForEach(compiled =>
        {
            var imports = Graph.OutEdges(compiled).Select(edge => edge.Target);
            StaticAnalyser.Analyse((CompiledLocalModule)compiled, [.. imports]);
        });
    }

    /// <summary>
    /// The script contents.
    /// </summary>
    /// <returns>
    /// The script contents.
    /// </returns>
    public override string GetPowerShellObject()
    {
        var sb = new StringBuilder();

        sb.AppendJoin('\n', Requirements.GetRequirements().Select(requirement =>
        {
            var data = new Hashtable() { { "NameSuffix", Convert.ToHexString(requirement.Hash) } };
            return requirement.GetInsertableLine(data);
        }));
        sb.AppendLine();

        if (ScriptParamBlock != null)
        {
            sb.AppendJoin('\n', ScriptParamBlock.Attributes.Select(attr => attr.Extent.Text));
            sb.AppendLine();

            sb.Append(ScriptParamBlock.Extent.Text);
            sb.AppendLine();
        }

        #region Begin Block
        sb.AppendLine("begin {");
        sb.AppendLine("    $Global:CompiledScript = $True;");
        sb.AppendLine("    $Global:EmbeddedModules = @{");
        Graph.Vertices.Skip(1).ToList().ForEach(module => sb.AppendLine($$"""        '{{module.ModuleSpec.Name}}' = {{module.GetPowerShellObject()}}"""));
        sb.AppendLine("};");

        sb.AppendLine(/*ps1*/ """
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

        sb.AppendLine("}");
        #endregion

        #region End Block
        sb.AppendLine($$"""
        end {
        {{Document.GetContent()}}
            $Env:PSModulePath = ($Env:PSModulePath -split ';' | Select-Object -Skip 1) -join ';';
        }
        """);
        #endregion

        return sb.ToString();
    }

    public override string StringifyContent() => throw new NotImplementedException();
    public override IEnumerable<string> GetExportedFunctions() => throw new NotImplementedException();

    private static string IndentString(string str, int indentBy, bool indentFirstLine = true)
    {
        var indent = new string(' ', indentBy);
        var lines = str.Split('\n');
        var indentedLines = lines.Select((line, index) =>
        {
            if (index == 0 && !indentFirstLine) { return line; }
            return indent + line;
        });

        return string.Join('\n', indentedLines);
    }
}
