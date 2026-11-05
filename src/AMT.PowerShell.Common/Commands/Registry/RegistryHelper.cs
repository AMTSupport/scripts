using System.Management.Automation;
using System.Runtime.InteropServices;

namespace AMT.PowerShell.Common.Commands.Registry;

internal static class RegistryHelper {
    private const string NotSupportedErrorId = "AMT.Registry.PlatformNotSupported";

    internal static bool IsRegistrySupported =>
        RuntimeInformation.IsOSPlatform(OSPlatform.Windows);

    internal static void WriteUnsupportedError(PSCmdlet cmdlet) =>
        cmdlet.WriteError(new ErrorRecord(
            new PlatformNotSupportedException("Registry operations are only supported on Windows."),
            NotSupportedErrorId,
            ErrorCategory.NotImplemented,
            null));
}
