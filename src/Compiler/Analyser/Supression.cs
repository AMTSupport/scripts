namespace Compiler.Analyser;

public record Supression(
    string Justification,
    Type Type,
    object? Data
);
