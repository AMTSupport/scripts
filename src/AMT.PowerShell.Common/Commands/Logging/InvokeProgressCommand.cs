// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Logging;

/// <summary>Iterates a collection with a progress bar, invoking a scriptblock for each item.</summary>
/// <remarks>
/// Items are retrieved via the <c>Get</c> scriptblock, then each item is passed to <c>Process</c>.
/// Progress is reported as a percentage; the bar is completed and dismissed when all items finish.
/// If an item throws, <c>FailedProcessItem</c> is called when provided; otherwise the item is
/// collected and a warning is emitted after the loop.
/// </remarks>
/// <example>
/// <code>
/// Invoke-Progress -Get { Get-ChildItem C:\ } -Process { param($f) Remove-Item $f -Force }
/// </code>
/// Removes each file under C:\ with a live progress bar.
/// </example>
[Cmdlet(VerbsLifecycle.Invoke, "Progress")]
public sealed class InvokeProgressCommand : PSCmdlet {
    /// <summary>Progress bar ID used to stack multiple concurrent progress bars; defaults to 0.</summary>
    [Parameter]
    public int Id { get; set; }

    /// <summary>Activity label displayed in the progress bar header; defaults to "Main" when omitted.</summary>
    [Parameter]
    public string? Activity { get; set; }

    /// <summary>
    /// Format template for the progress status line.
    /// Placeholders: <c>{0}</c> = completion percentage, <c>{1}</c> = current index, <c>{2}</c> = total count.
    /// Defaults to "Processing [item]..." when omitted.
    /// </summary>
    [Parameter]
    public string? Status { get; set; }

    /// <summary>ScriptBlock that returns the collection of items to iterate.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNull]
    public ScriptBlock Get { get; set; } = null!;

    /// <summary>ScriptBlock invoked for each item; receives the item as the first positional argument.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNull]
    public ScriptBlock Process { get; set; } = null!;

    /// <summary>ScriptBlock that returns a display name for an item; falls back to <c>ToString()</c> when omitted.</summary>
    [Parameter]
    [ValidateNotNull]
    public ScriptBlock? Format { get; set; }

    /// <summary>ScriptBlock invoked when <c>Process</c> throws for an item; when omitted, the item is added to a failed-items list and a warning is emitted.</summary>
    [Parameter]
    public ScriptBlock? FailedProcessItem { get; set; }

    protected override void ProcessRecord() {
        var activity = string.IsNullOrWhiteSpace(this.Activity) ? "Main" : this.Activity!;
        var items = ReadItems();

        if (items.Length == 0) {
            this.WriteProgress(new ProgressRecord(this.Id, activity, "No items found.") {
                PercentComplete = 100,
                RecordType = ProgressRecordType.Completed,
            });
            return;
        }

        var failedItems = new List<object?>();
        var percentPerItem = 99.0 / items.Length;
        var percentComplete = 0.0;

        for (var i = 0; i < items.Length; i++) {
            var item = items[i];
            var itemName = FormatItem(item);
            var status = string.IsNullOrWhiteSpace(this.Status)
                ? $"Processing [{itemName}]..."
                : FormatStatus(this.Status, percentComplete, i + 1, items.Length);

            this.WriteProgress(new ProgressRecord(this.Id, activity, status) {
                CurrentOperation = $"Processing [{itemName}]...",
                PercentComplete = (int)Math.Ceiling(percentComplete),
            });

            try {
                this.InvokeProcessItem(this.Process, item);
            } catch (Exception) {
                this.WriteWarning($"Failed to process item [{itemName}]");

                if (this.FailedProcessItem is not null) {
                    try {
                        this.InvokeProcessItem(this.FailedProcessItem, item);
                    } catch (Exception) {
                        this.WriteWarning($"Failed to process item [{itemName}] in failed process item block");
                    }
                } else {
                    failedItems.Add(item);
                }
            }

            percentComplete += percentPerItem;
        }

        this.WriteProgress(new ProgressRecord(this.Id, activity, "Completed") {
            PercentComplete = 100,
            RecordType = ProgressRecordType.Completed,
        });

        if (failedItems.Count > 0) {
            this.WriteWarning($"Failed to process {failedItems.Count} items");
        }
    }

    private object?[] ReadItems() {
        var items = new List<object?>();
        Flatten(this.Get.Invoke(), items);
        return items.ToArray();
    }

    private string FormatItem(object? item) {
        if (this.Format is not null) {
            var result = this.Format.InvokeReturnAsIs(item);
            var name = UnwrapScalar(result);

            if (!string.IsNullOrEmpty(name)) {
                return name;
            }
        }

        return item?.ToString() ?? string.Empty;
    }

    private void InvokeProcessItem(ScriptBlock scriptBlock, object? item) {
        var previous = this.SessionState.PSVariable.GetValue("ErrorActionPreference");
        this.SessionState.PSVariable.Set("ErrorActionPreference", ActionPreference.Stop);
        try {
            scriptBlock.InvokeReturnAsIs(item);
        } finally {
            this.SessionState.PSVariable.Set("ErrorActionPreference", previous);
        }
    }

    private static void Flatten(Collection<PSObject> results, List<object?> items) {
        foreach (var result in results) {
            Flatten(result?.BaseObject, items);
        }
    }

    private static void Flatten(object? value, List<object?> items) {
        if (value is null) {
            return;
        }

        if (value is string) {
            items.Add(value);
            return;
        }

        if (value is IEnumerable enumerable) {
            foreach (var element in enumerable) {
                Flatten(element, items);
            }

            return;
        }

        items.Add(value);
    }

    private static string UnwrapScalar(object? value) {
        if (value is PSObject psObject) {
            value = psObject.BaseObject;
        }

        return value?.ToString() ?? string.Empty;
    }

    private static string FormatStatus(string template, double percentComplete, int index, int total) {
        try {
            return string.Format(CultureInfo.InvariantCulture, template, percentComplete, index, total);
        } catch (FormatException) {
            return template;
        }
    }
}
