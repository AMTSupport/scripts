// Copyright (c) 2024 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Management.Automation.Language;

namespace Compiler.Text.Updater.Built;

public sealed class CommentRemovalUpdater() : TokenUpdater(
    5,
    static token => token.Kind == TokenKind.Comment,
    static comment => [],
    UpdateOptions.InsertInline
);
