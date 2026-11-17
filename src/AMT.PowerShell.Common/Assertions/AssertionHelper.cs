using System.Globalization;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Assertions;

public static class AssertionHelper {
    public static bool IsNotNull(object? value) => value is not null;

    public static bool AreEqual(object? actual, object? expected) => LanguagePrimitives.Equals(actual, expected, true, CultureInfo.InvariantCulture);
}
