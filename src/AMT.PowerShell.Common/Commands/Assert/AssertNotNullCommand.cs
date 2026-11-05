using System;
using System.Management.Automation;
using AMT.PowerShell.Common.Assertions;

namespace AMT.PowerShell.Common.Commands.Assert;

/// <summary>Assert that the input object is not null, throwing a terminating error if it is.</summary>
/// <remarks>
/// Checks <c>Object</c> using <see cref="Assertions.AssertionHelper.IsNotNull"/>.
/// When the value is null a terminating <see cref="System.ArgumentNullException"/> is written
/// with the error ID <c>AMT.Assert.NotNull</c>.
/// An optional custom message overrides the default <c>An unexpected null value was encountered.</c> text.
/// </remarks>
/// <example>
/// <code>Assert-NotNull -Object $value</code>
/// Throws a terminating error when <c>$value</c> is null.
/// </example>
/// <example>
/// <code>$service | Assert-NotNull -Message 'Service must not be null.'</code>
/// Passes silently when <c>$service</c> is non-null; emits the custom message otherwise.
/// </example>
[Cmdlet("Assert", "NotNull")]
public sealed class AssertNotNullCommand : PSCmdlet {
    private const string DefaultMessage = "An unexpected null value was encountered.";

    /// <summary>The value to check for null, accepted from the pipeline.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    [AllowNull]
    public object? Object { get; set; }

    /// <summary>Optional error message emitted when the assertion fails; overrides the default text.</summary>
    [Parameter]
    [AllowNull]
    public string? Message { get; set; }

    protected override void ProcessRecord() {
        if (AssertionHelper.IsNotNull(this.Object)) {
            return;
        }

        var errorMessage = string.IsNullOrWhiteSpace(this.Message)
            ? DefaultMessage
            : this.Message;

        this.ThrowTerminatingError(new ErrorRecord(
            new ArgumentNullException(nameof(this.Object), errorMessage),
            "AMT.Assert.NotNull",
            ErrorCategory.InvalidData,
            this.Object));
    }
}
