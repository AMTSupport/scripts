using System.Collections;
using System.Security.Cryptography;
using System.Text;

namespace Compiler.Requirements;

/// <summary>
/// Represents a requirement to include a using namespace statement in the code.
/// </summary>
public sealed class UsingNamespace : Requirement
{
    public string Namespace { get; }

    public UsingNamespace(string @namespace) : base()
    {
        SupportsMultiple = true;
        Weight = 75;

        Namespace = @namespace;
        Hash = SHA1.HashData(Encoding.UTF8.GetBytes(Namespace));
    }

    /// <summary>
    /// Gets the insertable line for the requirement.
    /// </summary>
    /// <returns>The insertable line.</returns>
    public override string GetInsertableLine(Hashtable _) => $"Using namespace {Namespace};";

    /// <summary>
    /// Checks if the requirement is compatible with another requirement.
    /// </summary>
    /// <param name="other">The other requirement.</param>
    /// <returns>True if compatible, false otherwise.</returns>
    public override bool IsCompatibleWith(Requirement other) => true;

    /// <summary>
    /// Gets the hash code of the requirement.
    /// </summary>
    /// <returns>The hash code.</returns>
    public override int GetHashCode() => Namespace.GetHashCode();
}
