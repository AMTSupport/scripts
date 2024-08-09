using System.Diagnostics.CodeAnalysis;
using System.Management.Automation.Language;

namespace Compiler.Analyser;

public record Suppression(
    [NotNull] Type Type,
    [AllowNull] object? Data,
    [NotNull] string Justification
);

[AttributeUsage(AttributeTargets.All, AllowMultiple = true, Inherited = false)]
public sealed class SuppressAnalyserAttribute(
    string CheckType,
    object? Data,
    string Justification
) : Attribute
{
    [return: NotNull]
    public Suppression GetSupression()
    {
        var assemblyName = "Compiler.Analyser.Rules." + CheckType;
        var type = Type.GetType(assemblyName, false, true) ?? throw new ArgumentException($"Could not find rule for suppression {CheckType}");
        return new Suppression(type, Data, Justification);
    }

    public static IEnumerable<SuppressAnalyserAttribute> FromAttributes(IEnumerable<AttributeAst> attributes)
    {
        foreach (var attr in attributes)
        {
            var suppression = FromAttributeAst(attr);
            if (suppression is not null) yield return suppression;
        }
    }

    public static SuppressAnalyserAttribute? FromAttributeAst([NotNull] AttributeAst attrAst)
    {
        ArgumentNullException.ThrowIfNull(attrAst, nameof(attrAst));

        if (attrAst.TypeName.GetReflectionType() != typeof(SuppressAnalyserAttribute)) return null;

        string? checkType = null;
        object? data = null;
        string? justification = null;

        if (attrAst != null)
        {
            var positionalArguments = attrAst.PositionalArguments;
            var namedArguments = attrAst.NamedArguments;

            int lastPositionalArgumentsOffset = -1;

            if (positionalArguments != null && positionalArguments.Count != 0)
            {
                int count = positionalArguments.Count;
                lastPositionalArgumentsOffset = positionalArguments[^1].Extent.StartOffset;
                switch (count)
                {
                    case 3:
                        if (positionalArguments[2] is not StringConstantExpressionAst justificationAst) throw new ArgumentException("Justification must be a string constant");
                        justification = justificationAst.Value;
                        goto case 2;
                    case 2:
                        data = positionalArguments[1].SafeGetValue();
                        goto case 1;
                    case 1:
                        if (positionalArguments[0] is not StringConstantExpressionAst checkTypeAst) throw new ArgumentException("CheckType must be a string constant");
                        checkType = checkTypeAst.Value;
                        goto default;
                    default:
                        break;
                }
            }

            if (namedArguments != null && namedArguments.Count != 0)
            {
                foreach (var name in namedArguments)
                {
                    if (name.Extent.StartOffset < lastPositionalArgumentsOffset) throw new ArgumentException("Named arguments must come after positional arguments");

                    var argumentName = name.ArgumentName;
                    if (argumentName.Equals("checkType", StringComparison.OrdinalIgnoreCase))
                    {
                        if (!string.IsNullOrWhiteSpace(checkType)) throw new ArgumentException("Named and positional arguments conflict for checkType");

                        if (name.Argument is not StringConstantExpressionAst checkTypeAst) throw new ArgumentException("CheckType must be a string constant");
                        checkType = checkTypeAst.Value;
                    }
                    else if (argumentName.Equals("data", StringComparison.OrdinalIgnoreCase))
                    {
                        if (data is not null) throw new ArgumentException("Named and positional arguments conflict for data");

                        data = name.Argument.SafeGetValue();
                    }
                    else if (argumentName.Equals("justification", StringComparison.OrdinalIgnoreCase))
                    {
                        if (!string.IsNullOrWhiteSpace(justification)) throw new ArgumentException("Named and positional arguments conflict for justification");

                        if (name.Argument is not StringConstantExpressionAst justificationAst) throw new ArgumentException("Justification must be a string constant");
                        justification = justificationAst.Value;
                    }
                }
            }
        }

        if (string.IsNullOrWhiteSpace(checkType)) throw new ArgumentException("CheckType is required");
        if (string.IsNullOrWhiteSpace(justification)) throw new ArgumentException("Justification is required");
        if (data is null) throw new ArgumentException("Data is required");

        return new SuppressAnalyserAttribute(checkType, data, justification);
    }
}
