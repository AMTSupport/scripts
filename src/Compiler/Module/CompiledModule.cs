using System.Security.Cryptography;
using System.Text;
using Compiler.Requirements;
using Compiler.Text;

namespace Compiler.Module;
public record CompiledModule(

    ContentType ContentType,
    ModuleSpec PreCompileModuleSpec,
    RequirementGroup Requirements,
    string Content,
    int IndentBy
)
{
    public ModuleSpec ModuleSpec => new(
        $"{PreCompileModuleSpec.Name}-{ContentHash}",
        PreCompileModuleSpec.Guid,
        PreCompileModuleSpec.MinimumVersion,
        PreCompileModuleSpec.MaximumVersion,
        PreCompileModuleSpec.RequiredVersion,
        PreCompileModuleSpec.InternalGuid
    );

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

    public static CompiledModule From(Module module, int indentBy)
    {
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
                Convert.ToHexString(remoteModule.BytesZip.Value),
                indentBy
            ),
            _ => throw new NotImplementedException()
        };
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
