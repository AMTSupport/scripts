using System.Collections;
using System.IO.Compression;
using System.Management.Automation.Language;
using System.Security.Cryptography;
using System.Text;
using Compiler.Requirements;
using Compiler.Text;
using NLog;

namespace Compiler.Module;

public record CompiledModule(
    ContentType ContentType,
    ModuleSpec PreCompileModuleSpec,
    RequirementGroup Requirements,
    string Content,
    int IndentBy
)
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    private readonly ZipArchive? MemoryZipArchive = ContentType switch
    {
        ContentType.UTF8String => null,
        ContentType.ZipHex => new ZipArchive(new MemoryStream(Convert.FromHexString(Content))),
        _ => throw new NotImplementedException()
    };

    public ModuleSpec ModuleSpec => new(
        $"{PreCompileModuleSpec.Name}-{ContentHash}",
        PreCompileModuleSpec.Guid,
        PreCompileModuleSpec.MinimumVersion,
        PreCompileModuleSpec.MaximumVersion,
        PreCompileModuleSpec.RequiredVersion,
        PreCompileModuleSpec.InternalGuid
    );

    public Ast ModuleAst => GetAst();

    public string ContentHash
    {
        get
        {
            var RawContentBytes = ContentType switch
            {
                ContentType.UTF8String => Encoding.UTF8.GetBytes(Content),
                ContentType.ZipHex => Convert.FromHexString(Content),
                _ => throw new NotImplementedException(),
            };
            var requirements = Requirements.GetRequirements();
            if (requirements.IsEmpty)
            {
                return Convert.ToHexString(SHA1.HashData(RawContentBytes));
            }
            else
            {
                var addedRequirements = Requirements.GetRequirements().Select(requirement => requirement.Hash).Aggregate((acc, next) => SHA256.HashData(acc.Concat(next).ToArray()));
                return Convert.ToHexString(SHA1.HashData([.. RawContentBytes.Concat(addedRequirements)]));
            }
        }
    }

    public static CompiledModule From(Module module, int indentBy)
    {
        Logger.Trace($"Compiling module {module.ModuleSpec.Name}");

        return module switch
        {
            LocalFileModule localFileModule => new CompiledModule(
                ContentType.UTF8String,
                localFileModule.ModuleSpec,
                localFileModule.Requirements,
                CompiledDocument.FromBuilder(localFileModule.Document, 0).GetContent(),
                indentBy
            ),
            RemoteModule remoteModule => new CompiledModule(
                ContentType.ZipHex,
                remoteModule.ModuleSpec,
                remoteModule.Requirements,
                Convert.ToHexString(remoteModule.ZipBytes.Value),
                indentBy
            ),
            _ => throw new NotImplementedException()
        };
    }

    public Ast GetAst()
    {
        switch (ContentType)
        {
            case ContentType.UTF8String:
                return Parser.ParseInput(Content, PreCompileModuleSpec.Name, out _, out _);
            case ContentType.ZipHex:
                {
                    var entry = MemoryZipArchive!.GetEntry($"{PreCompileModuleSpec.Name}.psm1")!;
                    using var entryStream = entry.Open();
                    using var reader = new StreamReader(entryStream);
                    return Parser.ParseInput(reader.ReadToEnd(), out _, out _);
                }
            default:
                throw new NotImplementedException();
        }
    }

    public IEnumerable<string> GetExportedFunctions()
    {
        switch (ContentType)
        {
            case ContentType.ZipHex:
                {
                    var entry = MemoryZipArchive!.GetEntry($"{PreCompileModuleSpec.Name}.psd1");
                    using var entryStream = entry!.Open();
                    using var reader = new StreamReader(entryStream);
                    var ast = Parser.ParseInput(reader.ReadToEnd(), out _, out _);

                    // Find the values of the FunctionsToExport and CmdletsToExport keys
                    var functionsToExport = ast.Find(testAst => testAst is HashtableAst hashtableAst && hashtableAst.KeyValuePairs.Any(keyValuePair => (string)keyValuePair.Item1.SafeGetValue() == "FunctionsToExport"), true) as HashtableAst;
                    var cmdletsToExport = ast.Find(testAst => testAst is HashtableAst hashtableAst && hashtableAst.KeyValuePairs.Any(keyValuePair => (string)keyValuePair.Item1.SafeGetValue() == "CmdletsToExport"), true) as HashtableAst;

                    // Join the two into a single list
                    // The values can be either a string or an array of strings
                    var exportedFunctions = new List<string>();
                    if (functionsToExport is not null)
                    {
                        var functionsToExportValue = functionsToExport.KeyValuePairs.First(keyValuePair => (string)keyValuePair.Item1.SafeGetValue() == "FunctionsToExport").Item2.SafeGetValue();
                        if (functionsToExportValue is string function)
                        {
                            exportedFunctions.Add(function);
                        }
                        else if (functionsToExportValue is IEnumerable functions)
                        {
                            exportedFunctions.AddRange(functions.Cast<string>());
                        }
                    }
                    if (cmdletsToExport is not null)
                    {
                        var cmdletsToExportValue = cmdletsToExport.KeyValuePairs.First(keyValuePair => (string)keyValuePair.Item1.SafeGetValue() == "CmdletsToExport").Item2.SafeGetValue();
                        if (cmdletsToExportValue is string cmdlet)
                        {
                            exportedFunctions.Add(cmdlet);
                        }
                        else if (cmdletsToExportValue is IEnumerable cmdlets)
                        {
                            exportedFunctions.AddRange(cmdlets.Cast<string>());
                        }
                    }
                    return exportedFunctions;
                }
            case ContentType.UTF8String:
                {
                    var ast = GetAst();
                    return AstHelper.FindAvailableFunctions(ast, true).Select(function => function.Name);
                }
            default:
                throw new NotImplementedException();
        }
    }

    public override string ToString()
    {
        var indentStr = new string(' ', IndentBy);
        var contentIndentStr = new string(' ', IndentBy + 4);

        string contentObject;
        switch (ContentType)
        {
            case ContentType.UTF8String:
                {
                    var sb = new StringBuilder();
                    sb.AppendLine($"<#ps1#> @'");

                    // Modules are using statements and must go below the #Requires statements
                    Requirements.GetRequirements().Where(requirement => requirement is not Compiler.Requirements.ModuleSpec).ToList().ForEach(requirement => sb.AppendLine(requirement.GetInsertableLine()));
                    Requirements.GetRequirements<ModuleSpec>().ToList().ForEach(requirement => sb.AppendLine(requirement.GetInsertableLine()));

                    sb.AppendLine(Content);

                    sb.AppendLine("'@;");
                    contentObject = sb.ToString();
                    break;
                }
            case ContentType.ZipHex:
                contentObject = $"'{Content}'";
                break;
            default:
                throw new NotImplementedException();
        }

        return $$"""
        {{indentStr}}'{{ModuleSpec.Name}}' = @{
        {{indentStr}}    Type = '{{ContentType}}';
        {{indentStr}}    Hash = '{{ContentHash}}';
        {{indentStr}}    Content = {{contentObject}}
        {{indentStr}}};
        """;
    }
}

public enum ContentType
{
    UTF8String,
    ZipHex
}
