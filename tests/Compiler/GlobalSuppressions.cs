// Copyright (c) 2024 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Diagnostics.CodeAnalysis;

[assembly: SuppressMessage(
    "Naming",
    "CA1707:Identifiers should not contain underscores",
    Justification = "Naming tests is easier this way",
    Scope = "namespaceanddescendants",
    Target = "~N:Compiler.Test"
)]

[assembly: SuppressMessage(
    "Naming",
    "CA1716:Identifiers should not match keywords",
    Justification = "Thats just how it is",
    Scope = "namespaceanddescendants",
    Target = "~N:Compiler.Test"
)]
