// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation.Language;

namespace Compiler.Text.Updater.Built;

public sealed class NewLineRemovalUpdater() : TokenUpdater(
    5,
    static token => token.Kind == TokenKind.NewLine,
    static newline => [],
    UpdateOptions.InsertInline
);
