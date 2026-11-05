// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Input;

/// <summary>Presents a GUI popup list and returns the item(s) the user selects.</summary>
/// <remarks>
/// Loops until a valid selection is made or <see cref="AllowNone"/> permits an empty result.
/// When <see cref="AllowMultiple"/> is set, all selected items are enumerated to the pipeline.
/// When <see cref="AllowNone"/> is set and nothing is selected, writes <c>$null</c>.
/// </remarks>
/// <example>
/// <code>$choice = Get-PopupSelection -Title 'Pick a driver' -Items $drivers</code>
/// Displays a popup list of drivers and returns the one the user picks.
/// </example>
[Cmdlet(VerbsCommon.Get, "PopupSelection")]
public sealed class GetPopupSelectionCommand : PSCmdlet {
    /// <summary>Heading displayed at the top of the popup dialog; defaults to <c>Select a(n) Item</c>.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public string Title { get; set; } = "Select a(n) Item";

    /// <summary>The collection of items to display in the popup list.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNullOrEmpty]
    public object[] Items { get; set; } = [];

    /// <summary>Allow the user to dismiss the dialog without selecting anything; writes <c>$null</c> in that case.</summary>
    [Parameter]
    public SwitchParameter AllowNone { get; set; }

    /// <summary>Allow the user to select more than one item; each selected item is written to the pipeline.</summary>
    [Parameter]
    public SwitchParameter AllowMultiple { get; set; }

    protected override void ProcessRecord() {
        InputOperations.EnsureValidationsVariable(this);

        while (true) {
            var selection = InputOperations.ReadPopupSelection(
                this,
                this.Title,
                this.Items,
                this.AllowNone.IsPresent,
                this.AllowMultiple.IsPresent);

            if (InputOperations.HasSelection(selection, this.AllowMultiple.IsPresent)) {
                if (this.AllowMultiple.IsPresent && selection is IEnumerable enumerable and not string) {
                    this.WriteObject(enumerable, enumerateCollection: true);
                } else {
                    this.WriteObject(selection);
                }

                return;
            }

            if (this.AllowNone.IsPresent) {
                this.WriteObject(null);
                return;
            }

            this.WriteWarning("No item was selected, re-running selection...");
        }
    }
}
