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

            return $"{this.ActualMessage}{module}";
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
        [NotNull] Option<string> message = default,
        [NotNull] Option<ModuleSpec> module = default
    ) : base(innerError) {
        this.ActualMessage = message.Match(
            some => some + Environment.NewLine + innerError.Message,
            () => innerError.Message
        );
        this.Module = module;
    }

    public override bool IsType<TE>() => (this.Inner.IsSome && this.Inner.Unwrap() is TE) || this is TE;

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

public record InvalidModulePathError : EnrichableExceptional {
    private InvalidModulePathError(string message) : base(message, 620) { }

    public virtual bool Equals(InvalidModulePathError? other) {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;

        return this.Message == other.Message;
    }

    public override int GetHashCode() => this.Message.GetHashCode();

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

    public override bool Equals(object? obj) {
        if (obj is null) return false;
        if (ReferenceEquals(this, obj)) return true;
        if (obj is not EnrichedException other) return false;

        return this.Module == other.Module
            && this.Exception == other.Exception;
    }

    public override Exception GetBaseException() => this.Exception.GetBaseException();

    public override int GetHashCode() => this.Exception.GetHashCode();

    public override string ToString() => $"{this.Exception}\nIn module {this.Module.Name}";
}

public record MultipleInstancesOfSingleRequirementError<T>(
    IEnumerable<T> Instances
) : EnrichableExceptional(
    $"""
    Multiple instances of type {nameof(T)} were found in the resolved modules.
    {string.Join(", ", Instances)}
    """,
    621
) where T : Requirement {
    public virtual bool Equals(MultipleInstancesOfSingleRequirementError<T>? other) {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;

        return this.Instances.SequenceEqual(other.Instances);
    }

    public override int GetHashCode() => HashCode.Combine(this.Instances);
}

public record IncompatableRequirementsError(
    IEnumerable<Requirement> ConflictingRequirements
) : EnrichableExceptional(
    $"""
    Some of the requirements are incompatible with each other.
    {string.Join(", ", ConflictingRequirements)}
    """,
    622
) {
    public virtual bool Equals(IncompatableRequirementsError? other) {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;

        return this.ConflictingRequirements.SequenceEqual(other.ConflictingRequirements);
    }

    public override int GetHashCode() => HashCode.Combine(this.ConflictingRequirements);
}

public record WrappedErrorWithDebuggableContent(
    Option<string> MaybeMessage,
    string Content,
    Error InnerException,
    Option<ModuleSpec> Module = default
) : EnrichableError(InnerException, MaybeMessage, Module) {
    public override Option<Error> Inner => this.InnerException;

    public virtual bool Equals(WrappedErrorWithDebuggableContent? other) {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;

        return this.Module == other.Module
            && this.InnerException == other.InnerException
            && this.Content == other.Content;
    }

    public override int GetHashCode() => HashCode.Combine(this.Content, this.InnerException, this.Module);
}

public sealed record InvalidInputError : Exceptional {
    private InvalidInputError(string message) : base(message, 623) { }

    public static InvalidInputError InvalidFileType(
        string inputPath,
        string expectedExtension
    ) => new($"The file {inputPath} is not a {expectedExtension} file");

    public static InvalidInputError NonExistent(string inputPath) => new($"The path {inputPath} does not exist");
}

public static class ErrorUtils {
    public static T Enrich<T>(
        this T error,
        ModuleSpec module
    ) where T : Error => error switch {
        WrappedErrorWithDebuggableContent wrapped when wrapped.Module.IsNone => (wrapped with { Module = module, InnerException = wrapped.InnerException.Enrich(module) } as T)!, // Safety: The WrappedErrorWithDebuggableContent return will always be a T.
        EnrichableExceptional enrichable when enrichable.Module.IsNone => (enrichable with { Module = module } as T)!, // Safety: The EnrichableExceptional return will always be a T.
        EnrichableError enrichable when enrichable.Module.IsNone => (enrichable with { Module = module } as T)!, // Safety: The EnrichableError return will always be a T.
        ManyErrors errors => (new ManyErrors(errors.Errors.Select(error => error.Enrich(module))) as T)!, // Safety: T will always be ManyErrors.
        _ => error
    };

    public static EnrichedException Enrich(
        this Exception exception,
        ModuleSpec module
    ) => exception switch {
        EnrichedException enriched => enriched,
        _ => new(exception, module) // Safety: T will always be an Exception.
    };
}
