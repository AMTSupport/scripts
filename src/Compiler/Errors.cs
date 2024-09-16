// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.Diagnostics.CodeAnalysis;
using Compiler.Requirements;
using LanguageExt;

namespace Compiler;

public abstract record EnrichableError : Error {
    public Option<ModuleSpec> Module { get; init; }

    public string ActualMessage { get; }

    public override string Message {
        get {
            var module = this.Module.Match(
                some => $" in module {some.Name}",
                () => ""
            );

            return $"{this.Message}{module}";
        }
    }

    public override bool IsExpected => this.Inner.AndThen(i => i.IsExpected).UnwrapOr(false);

    public override bool IsExceptional => this.Inner.AndThen(i => i.IsExceptional).UnwrapOr(false);

    public EnrichableError(
        string message,
        [NotNull] Option<ModuleSpec> module = default
    ) : base() {
        this.ActualMessage = message;
        this.Module = module;
    }

    public EnrichableError(
        [NotNull] Error innerError,
        [NotNull] Option<ModuleSpec> module = default
    ) : base(innerError) {
        this.ActualMessage = innerError.Message;
        this.Module = module;
    }

    public override bool Is<TE>() => (this.Inner.IsSome && this.Inner.Unwrap() is TE) || this is TE;

    public override ErrorException ToErrorException() {
        if (this.IsExceptional) {
            return new WrappedErrorExceptionalException(this);
        } else if (this.IsExpected) {
            return new WrappedErrorExpectedException(this);
        } else {
            return ErrorException.New(this.Code, this.Message);
        }
    }
}

public abstract record EnrichableExceptional : Exceptional {
    public Option<ModuleSpec> Module { get; init; }

    public EnrichableExceptional(
        string message,
        int code,
        [NotNull] Option<ModuleSpec> module = default
    ) : base(message, code) => this.Module = module;

    public EnrichableExceptional(
        [NotNull] Exceptional innerException,
        [NotNull] Option<ModuleSpec> module = default
    ) : base(innerException) => this.Module = module;

    public override string Message {
        get {
            var module = this.Module.Match(
                some => $" in module {some.Name}",
                () => ""
            );

            return $"{base.Message}{module}";
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

public sealed record WrappedErrorWithDebuggableContent(
    string Content,
    Error InnerException,
    Option<ModuleSpec> ModuleSpec = default
) : EnrichableError(InnerException, ModuleSpec);

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
