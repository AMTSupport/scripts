using System.Security.Cryptography;
using System.Text;

namespace Compiler.Requirements;

public record UsingNamespace(
    string Namespace
) : Requirement(true)
{
    public override uint Weight => 75;

    public override byte[] Hash => SHA1.HashData(Encoding.UTF8.GetBytes(Namespace));

    public override string GetInsertableLine() => $"Using namespace {Namespace};";

    public override bool IsCompatibleWith(Requirement other) => true;

    public override int GetHashCode() => Namespace.GetHashCode();
}
