using System.Security.Cryptography;
using System.Text;
using Compiler.Requirements;
using Compiler.Text;

namespace Compiler.Module;

public record CompiledModule(
    ContentType ContentType,
    ModuleSpec ModuleSpec,
    RequirementGroup Requirements,
    string Content,
    int IndentBy
)
{
    public string ContentHash
    {
        get
        {
            return ContentType switch
            {
                ContentType.UTF8String => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Content))),
                ContentType.ZipHex => Convert.ToHexString(SHA256.HashData(Convert.FromHexString(Content))),
                _ => throw new NotImplementedException(),
            };
        }
    }

    public static CompiledModule From(Module module, int indentBy = 0) => module switch
    {
        LocalFileModule localFileModule => new CompiledModule(
            ContentType.UTF8String,
            localFileModule.ModuleSpec,
            localFileModule.Requirements,
            CompiledDocument.FromBuilder(localFileModule.Document, indentBy + 4).GetContent(),
            indentBy
        ),
        RemoteModule remoteModule => new CompiledModule(
            ContentType.ZipHex,
            remoteModule.ModuleSpec,
            remoteModule.Requirements,
            Convert.ToHexString(remoteModule.BytesZip),
            indentBy
        ),
        _ => throw new NotImplementedException()
    };

    public override string ToString()
    {
        var indentStr = new string(' ', IndentBy);
        var contentObject = ContentType switch
        {
            ContentType.UTF8String => $$"""
            <#ps1#> @'
            {{Content}}
            '@
            """,
            ContentType.ZipHex => $"'${Content}'",
            _ => throw new NotImplementedException(),
        };

        return $$"""
        {{indentStr}}'{{ModuleSpec.Name}}' = @{
        {{indentStr}}    Type = '{{GetType().Name}}';
        {{indentStr}}    Hash = '{{ContentHash}}';
        {{indentStr}}    Content = {{contentObject}};
        {{indentStr}}};
        """;
    }
}

public enum ContentType
{
    UTF8String,
    ZipHex
}
