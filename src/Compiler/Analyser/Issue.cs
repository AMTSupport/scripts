using System.Management.Automation.Language;

namespace Compiler.Analyser;

public record Issue(
    IssueSeverity Severity,
    string Message,
    IScriptExtent Extent,
    Ast Parent
)
{
    public void Print()
    {
        AstHelper.PrintPrettyAstError(Extent, Parent, Message);
    }
}

public sealed class IssueException(
    string message,
    IScriptExtent extent,
    Ast parent,
    Exception? inner) : Exception(message, inner)
{
    public readonly Issue Issue = new(IssueSeverity.Error, message, extent, parent);

    public IssueException(
        string message,
        IScriptExtent extent,
        Ast parent) : this(message, extent, parent, null) { }
}

public enum IssueSeverity
{
    Error,
    Warning
}

