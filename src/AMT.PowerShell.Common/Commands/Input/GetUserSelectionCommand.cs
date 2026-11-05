// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.Generic;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Input;

/// <summary>Presents a list of choices to the user and returns the selected item.</summary>
/// <remarks>
/// Formats each choice using <see cref="FormatChoice"/> before display.
/// If the user submits an empty response on the first attempt, <see cref="DefaultChoice"/> is returned.
/// When <see cref="AllowNone"/> is set and the user cancels, <c>$null</c> is written;
/// otherwise cancellation throws <see cref="PipelineStoppedException"/>.
/// </remarks>
/// <example>
/// <code>$selected = Get-UserSelection -Title 'OS' -Question 'Pick a version:' -Choices @('Win10','Win11')</code>
/// Prompts the user to pick an operating system version.
/// </example>
[Cmdlet(VerbsCommon.Get, "UserSelection")]
public sealed class GetUserSelectionCommand : PSCmdlet {
    /// <summary>Heading displayed above the selection prompt.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNullOrEmpty]
    public string Title { get; set; } = string.Empty;

    /// <summary>The question text presented to the user above the choice list.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNullOrEmpty]
    public string Question { get; set; } = string.Empty;

    /// <summary>The array of items to present; also accessible via the <c>Items</c> alias.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNullOrEmpty]
    [Alias("Items")]
    public object[] Choices { get; set; } = [];

    /// <summary>Zero-based index of the choice pre-selected when the user submits an empty response on the first attempt.</summary>
    [Parameter]
    public int? DefaultChoice { get; set; }

    /// <summary>Allow the user to cancel or submit empty input; writes <c>$null</c> instead of throwing.</summary>
    [Parameter]
    public SwitchParameter AllowNone { get; set; }

    /// <summary>Script block that converts each choice object to a display string; defaults to <c>ToString()</c>.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public ScriptBlock FormatChoice { get; set; } = ScriptBlock.Create("param($Choice) $Choice.ToString()");

    protected override void ProcessRecord() {
        InputOperations.EnsureValidationsVariable(this);

        var formattedChoices = new string[this.Choices.Length];

        for (var i = 0; i < this.Choices.Length; i++) {
            formattedChoices[i] = FormatChoiceValue(this.Choices[i], this.FormatChoice);
        }

        var hasDefault = this.DefaultChoice.HasValue
            && this.DefaultChoice.Value >= 0
            && this.DefaultChoice.Value < formattedChoices.Length;
        var firstRun = true;

        while (true) {
            var selection = InputOperations.ReadSelection(
                this,
                this.Title,
                this.Question,
                formattedChoices,
                hasDefault ? this.DefaultChoice : null);

            if (selection.IsCanceled) {
                if (this.AllowNone.IsPresent) {
                    this.WriteObject(null);
                    return;
                }

                throw new PipelineStoppedException();
            }

            var selectedValue = (selection.Value ?? string.Empty).Trim();

            if (selectedValue.Length == 0) {
                if (firstRun && hasDefault) {
                    this.WriteObject(this.Choices[this.DefaultChoice!.Value]);
                    return;
                }

                if (this.AllowNone.IsPresent) {
                    this.WriteObject(null);
                    return;
                }
            }

            var selectedIndex = IndexOfChoice(formattedChoices, selectedValue);
            if (selectedIndex >= 0) {
                this.WriteObject(this.Choices[selectedIndex]);
                return;
            }

            firstRun = false;
            this.WriteWarning("Invalid selection, please try again...");
        }
    }

    private static int IndexOfChoice(IReadOnlyList<string> choices, string selection) {
        for (var i = 0; i < choices.Count; i++) {
            if (string.Equals(choices[i], selection, StringComparison.OrdinalIgnoreCase)) {
                return i;
            }
        }

        return -1;
    }

    private static string FormatChoiceValue(object? choice, ScriptBlock formatChoice) {
        if (formatChoice is null) {
            throw new ArgumentNullException(nameof(formatChoice));
        }

        var result = formatChoice.InvokeWithContext(
            functionsToDefine: null,
            variablesToDefine: new List<PSVariable> { new("_", choice) },
            args: [choice]);

        var formatted = result.Count > 0 ? result[0]?.ToString() : null;

        if (string.IsNullOrWhiteSpace(formatted)) {
            throw new ArgumentException("FormatChoice script block must return a non-empty string.");
        }

        return formatted!;
    }
}
