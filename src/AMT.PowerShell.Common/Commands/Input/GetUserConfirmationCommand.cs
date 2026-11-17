// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Input;

/// <summary>Prompts the user with a Yes/No question and returns the boolean answer.</summary>
/// <remarks>
/// Presents a selection prompt with <c>Yes</c> and <c>No</c> choices.
/// If the user enters an empty string on the first attempt, the <see cref="DefaultChoice"/> is used.
/// Invalid input causes the prompt to repeat. Cancelling throws <see cref="PipelineStoppedException"/>.
/// </remarks>
/// <example>
/// <code>$confirmed = Get-UserConfirmation -Title 'Delete files' -Question 'Are you sure?' -DefaultChoice $false</code>
/// Asks the user to confirm, defaulting to No.
/// </example>
[Cmdlet(VerbsCommon.Get, "UserConfirmation")]
[OutputType(typeof(bool))]
public sealed class GetUserConfirmationCommand : PSCmdlet {
    private static readonly string[] ChoiceValues = ["Yes", "No"];

    /// <summary>Heading displayed above the Yes/No prompt.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNullOrEmpty]
    public string Title { get; set; } = string.Empty;

    /// <summary>The question text presented to the user.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNullOrEmpty]
    public string Question { get; set; } = string.Empty;

    /// <summary>Pre-selected answer used when the user submits an empty response; <c>true</c> = Yes, <c>false</c> = No.</summary>
    [Parameter]
    public bool? DefaultChoice { get; set; }

    protected override void ProcessRecord() {
        InputOperations.EnsureValidationsVariable(this);

        var defaultChoice = this.DefaultChoice.HasValue
            ? (this.DefaultChoice.Value ? 0 : 1)
            : 1;

        var firstRun = true;

        while (true) {
            var selection = InputOperations.ReadSelection(
                this,
                this.Title,
                this.Question,
                ChoiceValues,
                defaultChoice);

            if (selection.IsCanceled) {
                throw new PipelineStoppedException();
            }

            var value = (selection.Value ?? string.Empty).Trim();
            if (firstRun && value.Length == 0) {
                value = ChoiceValues[defaultChoice];
            }

            if (string.Equals(value, "Yes", StringComparison.OrdinalIgnoreCase)) {
                this.WriteObject(true);
                return;
            }

            if (string.Equals(value, "No", StringComparison.OrdinalIgnoreCase)) {
                this.WriteObject(false);
                return;
            }

            firstRun = false;
            this.WriteWarning("Invalid selection, please try again...");
        }
    }
}
