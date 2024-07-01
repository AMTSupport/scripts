using System.Security.Cryptography;
using System.Text;

namespace Compiler.Requirements;

public enum PSEdition { Desktop, Core }

/// <summary>
/// Represents a PowerShell edition requirement.
/// </summary>
public record PSEditionRequirement(PSEdition Edition) : Requirement(false)
{
    public override byte[] Hash => SHA1.HashData(Encoding.UTF8.GetBytes(Edition.ToString()));

    /// <summary>
    /// Gets the insertable line for the requirement.
    /// </summary>
    /// <returns>The insertable line for the requirement.</returns>
    public override string GetInsertableLine() => $"#Requires -PSEdition {Edition}";

    /// <summary>
    /// Determines whether this requirement is compatible with another requirement.
    /// </summary>
    /// <param name="other">The other requirement.</param>
    /// <returns><c>true</c> if this requirement is compatible with the other requirement; otherwise, <c>false</c>.</returns>
    public override bool IsCompatibleWith(Requirement other)
    {
        if (other is PSEditionRequirement otherEdition)
        {
            return Edition == otherEdition.Edition;
        }

        return true;
    }
}
