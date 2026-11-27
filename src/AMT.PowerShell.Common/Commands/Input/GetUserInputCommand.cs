// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Security;

namespace AMT.PowerShell.Common.Commands.Input;

/// <summary>Prompts the user for free-form text input and returns the validated value.</summary>
/// <remarks>
/// Re-prompts until the entered value passes optional <see cref="Validate"/> validation and is
/// non-empty (unless <see cref="AllowEmpty"/> is set). When <see cref="AsSecureString"/> is set
/// the value is returned as a <see cref="System.Security.SecureString"/> and not persisted to history.
/// </remarks>
/// <example>
/// <code>$name = Get-UserInput -Title 'Setup' -Question 'Enter your name:' -Validate { $_ -match '\w+' }</code>
/// Prompts for a non-empty name and validates it against the supplied script block.
/// </example>
[Cmdlet(VerbsCommon.Get, "UserInput")]
[OutputType(typeof(string), typeof(System.Security.SecureString))]
public sealed class GetUserInputCommand : PSCmdlet {
    /// <summary>Heading displayed above the input prompt.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNullOrEmpty]
    public string Title { get; set; } = string.Empty;

    /// <summary>The prompt text shown to the user; also accessible via the <c>Prompt</c> alias.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNullOrEmpty]
    [Alias("Prompt")]
    public string Question { get; set; } = string.Empty;

    /// <summary>Optional script block that receives the raw input string and returns a truthy value when valid.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public ScriptBlock? Validate { get; set; }

    /// <summary>Return the input as a <see cref="System.Security.SecureString"/> and suppress history saving.</summary>
    [Parameter]
    public SwitchParameter AsSecureString { get; set; }

    /// <summary>Prevent the entered value from being saved to the session input history.</summary>
    [Parameter]
    public SwitchParameter DontSaveInputs { get; set; }

    /// <summary>Save input to a prompt-specific history file keyed by a hash of <see cref="Title"/> and <see cref="Question"/>.</summary>
    [Parameter]
    public SwitchParameter SaveInputAsUniqueHistory { get; set; }

    /// <summary>Allow the user to submit an empty string; writes <c>$null</c> in that case.</summary>
    [Parameter]
    public SwitchParameter AllowEmpty { get; set; }

    protected override void ProcessRecord() {
        InputOperations.EnsureValidationsVariable(this);


        while (true) {
            var rawInput = InputOperations.ReadInput(
                this,
                this.Title,
                this.Question,
                this.AsSecureString.IsPresent);

            if (rawInput is null) {
                throw new PipelineStoppedException();
            }

            var userInput = rawInput.Trim();

            if (string.IsNullOrEmpty(userInput)) {
                if (this.AllowEmpty.IsPresent) {
                    this.WriteObject(null);
                    return;
                }

                this.WriteWarning("Invalid input, please try again...");
                continue;
            }

            if (!IsValid(userInput, this.Validate)) {
                this.WriteWarning("Invalid input, please try again...");
                continue;
            }

            if (this.AsSecureString.IsPresent) {
                var secure = new SecureString();
                foreach (var character in userInput) {
                    secure.AppendChar(character);
                }

                secure.MakeReadOnly();
                this.WriteObject(secure);
                return;
            }

            this.WriteObject(userInput);
            return;
        }
    }

    private static bool IsValid(string value, ScriptBlock? validate) {
        if (validate is null) {
            return true;
        }

        try {
            var result = validate.InvokeWithContext(
                functionsToDefine: null,
                variablesToDefine: new List<PSVariable> { new("_", value) },
                args: [value]);

            return result.Count > 0
                && LanguagePrimitives.IsTrue(result[0]?.BaseObject);
        } catch {
            try {
                var result = validate.InvokeReturnAsIs(value);
                return LanguagePrimitives.IsTrue(result);
            } catch {
                return false;
            }
        }
    }
}
