// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics.CodeAnalysis;
using System.Management.Automation.Language;
using LanguageExt;

namespace Compiler.Analyser;

public record Suppression(
    [NotNull] Type Type,
    [AllowNull] object? Data,
    [NotNull] string Justification
) {
    public override int GetHashCode() => HashCode.Combine(this.Type, this.Data, this.Justification);

    public override string ToString() => $"[{this.Type.Name}] {this.Justification} ({this.Data})";
}

[AttributeUsage(AttributeTargets.All, AllowMultiple = true, Inherited = false)]
public sealed class SuppressAnalyserAttribute(
    string checkType,
    object? data,
    string justification
) : Attribute {
    [return: NotNull]
    public Suppression GetSupression() {
        var assemblyName = "Compiler.Analyser.Rules." + checkType;
        var type = Type.GetType(assemblyName, false, true) ?? throw new ArgumentException($"Could not find rule for suppression {checkType}");
        return new Suppression(type, data, justification);
    }

    [return: NotNull]
    public static Fin<IEnumerable<SuppressAnalyserAttribute>> FromAttributes(IEnumerable<AttributeAst> attributes) {
        var suppressions = new List<SuppressAnalyserAttribute>();
        var issues = ManyErrors.Empty;

        foreach (var attr in attributes) {
            var suppressionResult = FromAttributeAst(attr);
            if (suppressionResult.IsErr(out var err, out var suppressionOpt)) {
                issues = issues.Combine(err);
                continue;
            } else if (suppressionOpt.IsSome(out var suppression)) {
                suppressions.Add(suppression);
            }
        }

        return issues.Count == 0
            ? FinSucc<IEnumerable<SuppressAnalyserAttribute>>(suppressions)
            : FinFail<IEnumerable<SuppressAnalyserAttribute>>(issues);
    }

    [return: NotNull]
    public static Fin<Option<SuppressAnalyserAttribute>> FromAttributeAst([NotNull] AttributeAst attrAst) {
        ArgumentNullException.ThrowIfNull(attrAst);

        var typeName = attrAst.TypeName;
        var attributeSuffixed = typeName.FullName.EndsWith("Attribute", StringComparison.OrdinalIgnoreCase) ? typeName.FullName : typeName.FullName + "Attribute";
        var hasNamespace = typeName.Extent.Text.Contains('.');

        if (!(typeName.GetReflectionAttributeType() == typeof(SuppressAnalyserAttribute)
            || (hasNamespace && attributeSuffixed == typeof(SuppressAnalyserAttribute).FullName)
            || (!hasNamespace && attributeSuffixed == nameof(SuppressAnalyserAttribute))
        )) return FinSucc<Option<SuppressAnalyserAttribute>>(None);

        string? checkType = null;
        object? data = null;
        string? justification = null;

        var positionalArguments = attrAst.PositionalArguments;
        var namedArguments = attrAst.NamedArguments;

        Issue IncorrectDataType(string name, string expected, IScriptExtent extent) => Issue.Error(
            $"{name} must be a {expected}",
            extent,
            attrAst.GetRootParent()
        );

        var lastPositionalArgumentsOffset = -1;
        if (positionalArguments != null && positionalArguments.Count != 0) {
            var count = positionalArguments.Count;
            lastPositionalArgumentsOffset = positionalArguments[^1].Extent.StartOffset;
            switch (count) {
                case 3:
                    if (positionalArguments[2] is not StringConstantExpressionAst justificationAst) {
                        return IncorrectDataType("Justification", "string constant", positionalArguments[2].Extent);
                    }
                    justification = justificationAst.Value;
                    goto case 2;
                case 2:
                    data = positionalArguments[1].SafeGetValue();
                    goto case 1;
                case 1:
                    if (positionalArguments[0] is not StringConstantExpressionAst checkTypeAst) {
                        return IncorrectDataType("CheckType", "string constant", positionalArguments[0].Extent);
                    }
                    checkType = checkTypeAst.Value;
                    goto default;
                default:
                    break;
            }
        }

        if (namedArguments != null && namedArguments.Count != 0) {
            foreach (var name in namedArguments) {
                if (name.Extent.StartOffset < lastPositionalArgumentsOffset) {
                    return Issue.Error(
                        "Named arguments must come after positional arguments",
                        name.Extent,
                        attrAst.GetRootParent()
                    );
                }

                var argumentName = name.ArgumentName;
                if (argumentName.Equals("checkType", StringComparison.OrdinalIgnoreCase)) {
                    if (!string.IsNullOrWhiteSpace(checkType)) {
                        return Issue.Error(
                            "Named and positional arguments conflict for checkType",
                            name.Extent,
                            attrAst.GetRootParent()
                        );
                    }

                    if (name.Argument is not StringConstantExpressionAst checkTypeAst) {
                        return Issue.Error(
                            "CheckType must be a string constant",
                            name.Extent,
                            attrAst.GetRootParent()
                        );
                    }
                    checkType = checkTypeAst.Value;
                } else if (argumentName.Equals("data", StringComparison.OrdinalIgnoreCase)) {
                    if (data is not null) {
                        return Issue.Error(
                            "Named and positional arguments conflict for data",
                            name.Extent,
                            attrAst.GetRootParent()
                        );
                    }

                    data = name.Argument.SafeGetValue();
                } else if (argumentName.Equals("justification", StringComparison.OrdinalIgnoreCase)) {
                    if (!string.IsNullOrWhiteSpace(justification)) {
                        return Issue.Error(
                            "Named and positional arguments conflict for justification",
                            name.Extent,
                            attrAst.GetRootParent()
                        );
                    }

                    if (name.Argument is not StringConstantExpressionAst justificationAst) {
                        return Issue.Error(
                            "Justification must be a string constant",
                            name.Extent,
                            attrAst.GetRootParent()
                        );
                    }
                    justification = justificationAst.Value;
                }
            }
        }

        Issue IsRequired(string name) => Issue.Error(
            $"{name} is required",
            attrAst.Extent,
            attrAst.GetRootParent()
        );

        if (string.IsNullOrWhiteSpace(checkType)) return IsRequired("CheckType");
        if (string.IsNullOrWhiteSpace(justification)) return IsRequired("Justification");
        if (data is null) return IsRequired("Data");

        switch (data) {
            case string:
                break;
            case object[] dataArray when dataArray.All(v => v is string):
                break;
            default:
                throw new ArgumentException($"Data must be a string or an array of strings, got {data.GetType().Name}");
        }

        return Some(new SuppressAnalyserAttribute(checkType, data, justification));
    }
}
