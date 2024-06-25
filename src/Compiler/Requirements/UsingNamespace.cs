namespace Compiler.Requirements;

public record UsingNamespace(
    string Namespace
) : Requirement(true, 75)
{
    public override string GetInsertableLine() => $"Using namespace {Namespace};";

    public override bool IsCompatibleWith(Requirement other) => true;

    public override int GetHashCode()
    {
        return Namespace.GetHashCode();
    }
}
