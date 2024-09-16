// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics.CodeAnalysis;
using System.Diagnostics.Contracts;
using System.Management.Automation.Language;
using System.Runtime.Serialization;
using Compiler.Requirements;
using LanguageExt;

namespace Compiler.Analyser;

[DataContract]
public record Issue(
    [NotNull] IssueSeverity Severity,
    [NotNull] string ActualMessage,
    [NotNull] IScriptExtent Extent,
    [NotNull] Ast Parent,
    [NotNull] Option<ModuleSpec> Module = default
) : EnrichableExceptional(ActualMessage, 620, Module) {
    public override bool IsExceptional { get; } = Severity == IssueSeverity.Error;

    public override bool IsExpected { get; } = Severity == IssueSeverity.Warning;

    public override string Message => this.ToString();

    public override string ToString() => AstHelper.GetPrettyAstError(
        this.Extent,
        this.Parent,
        Some(this.ActualMessage),
        this.Module.Map(mod => mod is PathedModuleSpec pathed ? pathed.FullPath : mod.Name)
    );

    [Pure]
    [return: NotNull]
    public static Issue Error(
        [NotNull] string message,
        [NotNull] IScriptExtent extent,
        [NotNull] Ast parent,
        [NotNull] Option<ModuleSpec> module = default) => new(IssueSeverity.Error, message, extent, parent, module);

    [Pure]
    [return: NotNull]
    public static Issue Warning(
        [NotNull] string message,
        [NotNull] IScriptExtent extent,
        [NotNull] Ast parent,
        [NotNull] Option<ModuleSpec> module = default) => new(IssueSeverity.Warning, message, extent, parent, module);

    public override bool Is<TE>() => false;
    public T Enrich<T>(ModuleSpec module) where T : Exceptional => throw new NotImplementedException();
}

public enum IssueSeverity {
    Error,
    Warning
}

