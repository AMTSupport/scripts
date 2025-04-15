// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics.CodeAnalysis;
using System.Diagnostics.Contracts;
using System.Management.Automation.Language;
using System.Runtime.CompilerServices;
using LanguageExt;
using LanguageExt.UnsafeValueAccess;

namespace Compiler;

/// <summary>
/// Helper methods to make it a little more rust-like.
/// </summary>
[ExcludeFromCodeCoverage]
public static class Utils {
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Option<T> AsOption<T>(this T? value) where T : class =>
        value == null ? Option<T>.None : Option<T>.Some(value);

    #region AndThen & AndThenTry
    [return: NotNull]
    [Pure, MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Option<TOut> AndThen<TIn, TOut>(
        [NotNull] this Option<TIn> option,
        [NotNull] Func<TIn, TOut> func
    ) => option.Map(func);

    [return: NotNull]
    [Pure, MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Option<TOut> AndThen<TIn, TOut>(
        [NotNull] this Option<TIn> option,
        [NotNull] Func<TIn, Option<TOut>> func
    ) => option.Bind(func);

    [return: NotNull]
    [Pure, MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Option<TOut> AndThenTry<TIn, TOut>(
        [NotNull] this Option<TIn> option,
        [NotNull] Func<TIn, TOut> func
    ) => option.Bind(value => {
        try {
            return Some(func(value));
        } catch {
            return None;
        }
    });

    [return: NotNull]
    [Pure, MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Option<TOut> AndThenTry<TIn, TOut>(
        [NotNull] this Option<TIn> option,
        [NotNull] Func<TIn, Option<TOut>> func
    ) => option.Bind(value => {
        try {
            return func(value);
        } catch {
            return None;
        }
    });

    [return: NotNull]
    [Pure, MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Fin<TOut> AndThen<TIn, TOut>(
        [NotNull] this Option<TIn> option,
        [NotNull] Func<TIn, Fin<TOut>> func,
        [NotNull] Func<Error> error
    ) => option.Map(func).UnwrapOrElse(() => Fin<TOut>.Fail(error()));

    [return: NotNull]
    [Pure, MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Fin<TOut> AndThen<TIn, TOut>(
        [NotNull] this Option<TIn> option,
        [NotNull] Func<TIn, Fin<TOut>> func
    ) => option.AndThen(func, () => Error.New("Option was None"));

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Fin<TOut> AndThenTry<TIn, TOut>(
        [NotNull] this Option<TIn> option,
        [NotNull] Func<TIn, Fin<TOut>> func,
        [NotNull] Func<TIn, Error> error
    ) => option.AndThenTry(value => {
        try {
            return func(value);
        } catch {
            return FinFail<TOut>(error(value));
        }
    });

    [return: NotNull]
    [Pure, MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Fin<TOut> AndThenTry<TIn, TOut>(
        [NotNull] this Option<TIn> option,
        [NotNull] Func<TIn, Fin<TOut>> func
    ) => option.AndThenTry(func, _ => Error.New("An error occurred while trying to map the option"));

    [return: NotNull]
    [Pure, MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Fin<TOut> AndThen<TIn, TOut>(
        [NotNull] this Fin<TIn> fin,
        [NotNull] Func<TIn, TOut> func
    ) => fin.Map(func);

    [return: NotNull]
    [Pure, MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Fin<TOut> AndThenTry<TIn, TOut>(
        [NotNull] this Fin<TIn> fin,
        [NotNull] Func<TIn, TOut> func
    ) => fin.Bind(value => {
        try {
            return func(value);
        } catch (Exception err) {
            return FinFail<TOut>(err);
        }
    });

    [return: NotNull]
    [Pure, MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Fin<TOut> AndThenTry<TIn, TOut>(
        [NotNull] this Fin<TIn> fin,
        [NotNull] Func<TIn, TOut> func,
        [NotNull] Func<TIn, Exception, Error> error
    ) => fin.Bind(value => {
        try {
            return func(value);
        } catch (Exception err) {
            return FinFail<TOut>(error(value, err));
        }
    });

    [return: NotNull]
    [Pure, MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Fin<TOut> AndThen<TIn, TOut>(
        [NotNull] this Fin<TIn> fin,
        [NotNull] Func<TIn, Fin<TOut>> func
    ) => fin.Bind(func);

    [return: NotNull]
    [Pure, MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Fin<TOut> AndThenTry<TIn, TOut>(
        [NotNull] this Fin<TIn> fin,
        [NotNull] Func<TIn, Fin<TOut>> func
    ) => fin.Bind(value => {
        try {
            return func(value);
        } catch (Exception err) {
            return FinFail<TOut>(err);
        }
    });

    [return: NotNull]
    [Pure, MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Fin<TOut> AndThenTry<TIn, TOut>(
        [NotNull] this Fin<TIn> fin,
        [NotNull] Func<TIn, Fin<TOut>> func,
        [NotNull] Func<TIn, Exception, Error> error
    ) => fin.Bind(value => {
        try {
            return func(value);
        } catch (Exception err) {
            return FinFail<TOut>(error(value, err));
        }
    });
    #endregion

    #region Tap
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Option<T> Tap<T>(this Option<T> option, Action<T> action) =>
        option.Do(action);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Option<T> TapNone<T>(this Option<T> option, Action action) {
        if (option.IsNone) action();
        return option;
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Fin<T> Tap<T>(this Fin<T> fin, Action<T> action) {
        fin.IfSucc(action);
        return fin;
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Fin<Option<T>> TapOpt<T>(this Fin<Option<T>> fin, Action<T> action) =>
        fin.Tap(option => option.IfSome(action));

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Fin<T> TapFail<T>(this Fin<T> fin, Action<Error> action) {
        fin.IfFail(action);
        return fin;
    }
    #endregion

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Fin<Option<T>> FailIf<T>(this Option<T> option, Predicate<T> predicate, Func<T, Error> error) => option.Match(
        Some: value => predicate(value) ? error(value) : Some(value),
        None: Fin<Option<T>>.Succ(None)
    );

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Fin<Option<T>> FailIf<T>(this Option<T> option, Predicate<T> predicate, Error error) => option.Match(
        Some: value => predicate(value) ? error : Some(value),
        None: Fin<Option<T>>.Succ(None)
    );

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Fin<T> FailIf<T>(this Fin<T> fin, Predicate<T> predicate, Func<T, Error> error) =>
        fin.Bind(value => predicate(value) ? Fin<T>.Fail(error(value)) : Fin<T>.Succ(value));

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Fin<T> FailIf<T>(this Fin<T> fin, Predicate<T> predicate, Error error) =>
        fin.Bind(value => predicate(value) ? Fin<T>.Fail(error) : Fin<T>.Succ(value));

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Fin<Option<T>> FailIfOpt<T>(this Fin<Option<T>> fin, Predicate<T> predicate, Func<T, Error> error) => fin.Bind(option => option.Match(
        Some: value => predicate(value) ? error(value) : Some(value),
        None: Fin<Option<T>>.Succ(None)
    ));

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Fin<Option<T>> FailIfOpt<T>(this Fin<Option<T>> fin, Predicate<T> predicate, Error error) => fin.Bind(option => option.Match(
        Some: value => predicate(value) ? Fin<Option<T>>.Fail(error) : Fin<Option<T>>.Succ(Some(value)),
        None: Fin<Option<T>>.Succ(None)
    ));

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Fin<Option<TOut>> BindOption<TIn, TOut>(this Fin<Option<TIn>> fin, Func<TIn, Fin<Option<TOut>>> func) => fin.Bind(option => option.Match(
        Some: func,
        None: Fin<Option<TOut>>.Succ(None)
    ));

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Option<T> OrElse<T>(this Option<T> option, Func<Option<T>> other) => option.BiBind(
        Some: _ => option,
        None: () => other()
    );

    #region Unwrap
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static T Unwrap<T>(this Option<T> option) where T : notnull => option.ValueUnsafe()!;

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static T UnwrapOr<T>(this Option<T> option, T defaultValue) => option.Match(
        Some: value => value,
        None: defaultValue
    );

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static T UnwrapOrElse<T>(this Option<T> option, Func<T> defaultValue) => option.Match(
        Some: value => value,
        None: defaultValue()
    );

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static T Unwrap<T>(this Fin<T> fin) => fin.ThrowIfFail();

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static T UnwrapOr<T>(this Fin<T> fin, T defaultValue) => fin.Match(
        Succ: value => value,
        Fail: _ => defaultValue
    );

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static T UnwrapOrElse<T>(this Fin<T> fin, Func<T> defaultValue) => fin.Match(
        Succ: value => value,
        Fail: error => defaultValue()
    );

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Error UnwrapError<T>(this Fin<T> fin) => (Error)fin;
    #endregion

    #region Is Decontruct bools
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static bool IsSome<T>(
        this Option<T> option,
        [NotNullWhen(true)] out T? value
    ) where T : notnull {
        if (option.IsSome) {
            value = option.ValueUnsafe()!;
            return true;
        }

        value = default;
        return false;
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static bool IsOk<T>(
        this Fin<T> fin,
        [NotNullWhen(true)] out T? value,
        [NotNullWhen(false)] out Error? error
) {
        if (fin.IsSucc) {
            value = (T)fin!; // This is safe because we know it's a success
            error = default;
            return true;
        }

        error = (Error)fin!; // This is safe because we know it's a failure
        value = default;
        return false;
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static bool IsErr<T>(
        this Fin<T> fin,
        [NotNullWhen(true)] out Error? error,
        [NotNullWhen(false)] out T? value
    ) => !fin.IsOk(out value, out error);
    #endregion

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Ast GetRootParent(this Ast ast) {
        var parent = ast.Parent;
        while (parent?.Parent != null) parent = parent.Parent;
        return parent ?? ast;
    }
}
