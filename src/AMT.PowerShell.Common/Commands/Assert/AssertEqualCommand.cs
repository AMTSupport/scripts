using System;
using System.Management.Automation;
using AMT.PowerShell.Common.Assertions;

namespace AMT.PowerShell.Common.Commands.Assert;

/// <summary>Assert that two objects are equal, throwing a terminating error if they differ.</summary>
/// <remarks>
/// Compares <c>Object</c> and <c>Expected</c> using <see cref="Assertions.AssertionHelper.AreEqual"/>.
/// When they are not equal a terminating <see cref="System.InvalidOperationException"/> is written
/// with the error ID <c>AMT.Assert.Equal</c>.
/// An optional custom message overrides the default <c>Object [{0}] does not equal expected value [{1}]</c> template.
/// </remarks>
/// <example>
/// <code>Assert-Equal -Object $result -Expected 'expected-value'</code>
/// Throws a terminating error when <c>$result</c> is not equal to <c>'expected-value'</c>.
/// </example>
/// <example>
/// <code>'actual' | Assert-Equal -Expected 'actual'</code>
/// Passes silently because the pipeline value matches the expected value.
/// </example>
[Cmdlet("Assert", "Equal")]
public sealed class AssertEqualCommand : PSCmdlet {
    private const string ErrorMessageTemplate = "Object [{0}] does not equal expected value [{1}].";

    /// <summary>The value under test, accepted from the pipeline.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public object? Object { get; set; }

    /// <summary>The value that <c>Object</c> must equal.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    public object? Expected { get; set; }

    /// <summary>Optional error message emitted when the assertion fails; overrides the default template.</summary>
    [Parameter]
    [AllowNull]
    public string? Message { get; set; }

    protected override void ProcessRecord() {
        if (AssertionHelper.AreEqual(this.Object, this.Expected)) {
            return;
        }

        var errorMessage = string.IsNullOrWhiteSpace(this.Message)
            ? string.Format(ErrorMessageTemplate, this.Object, this.Expected)
            : this.Message;

        this.ThrowTerminatingError(new ErrorRecord(
            new InvalidOperationException(errorMessage),
            "AMT.Assert.Equal",
            ErrorCategory.InvalidData,
            this.Object));
    }
}
