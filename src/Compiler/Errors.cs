// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.Diagnostics.CodeAnalysis;
using Compiler.Requirements;
using LanguageExt;

namespace Compiler;

public abstract record EnrichableExceptional(
    string ActualMessage,
    int Code,
    [NotNull] Option<ModuleSpec> Module = default
) : Exceptional(
    ActualMessage,
    Code
) {
    public override string Message {
        get {
            var module = this.Module.Match(
                some => $" in module {some.Name}",
                () => ""
            );

            return $"{this.ActualMessage}{module}";
        }
    }

    public override Exception ToException() => base.ToErrorException();
};

public sealed record InvalidModulePathError : EnrichableExceptional {
    private InvalidModulePathError(string message) : base(message, 620) { }

    public static InvalidModulePathError NotAFile(string notFilePath) => new($"The module path must be a file, received {notFilePath}");

    public static InvalidModulePathError ParentNotADirectory(string parentPath) => new($"The parent path must be a directory, received {parentPath}");

    public static InvalidModulePathError NotAnAbsolutePath(string providedPath) => new($"The parent path must be an absolute path, received {providedPath}");
}

public sealed class EnrichedException([NotNull] Exception exception, [NotNull] ModuleSpec module) : Exception {
    public readonly Exception Exception = exception;

    public readonly ModuleSpec Module = module;

    public override string Message => $"{this.Exception.Message} in module {this.Module.Name}";

    public override string StackTrace => this.Exception.StackTrace ?? "";

    public override IDictionary Data => this.Exception.Data;

    public override bool Equals(object? obj) => this.Exception.Equals(obj);

    public override Exception GetBaseException() => this.Exception.GetBaseException();

    public override int GetHashCode() => this.Exception.GetHashCode();

    public override string ToString() => $"{this.Exception}\nIn module {this.Module.Name}";
}

public sealed record MultipleInstancesOfSingleRequirementError<T>(
    IEnumerable<T> Instances
) : EnrichableExceptional(
    $"""
    Multiple instances of type {nameof(T)} were found in the resolved modules.
    {string.Join(", ", Instances)}
    """,
    621
) where T : Requirement;

public sealed record IncompatableRequirementsError(
    IEnumerable<Requirement> ConflictingRequirements
) : EnrichableExceptional(
    $"""
    Some of the requirements are incompatible with each other.
    {string.Join(", ", ConflictingRequirements)}
    """,
    622
);

public static class ErrorUtils {
    public static T Enrich<T>(
        this T error,
        ModuleSpec module
    ) where T : Error => error switch {
        EnrichableExceptional enrichable => (enrichable with { Module = module } as T)!, // Safety: The EnrichableExceptional return will always be a T.
        ManyErrors errors => (new ManyErrors(errors.Errors.Select(error => error.Enrich(module))) as T)!, // Safety: T will always be ManyErrors.
        _ => error
    };

    public static EnrichedException Enrich(
        this Exception exception,
        ModuleSpec module
    ) => new(exception, module); // Safety: T will always be an Exception.
}
