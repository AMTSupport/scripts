using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace AMT.PowerShell.Common.Commands.Ensure;

// Shared Windows P/Invoke helpers for elevation-aware checks.
// Only call IsCurrentProcessElevated() after confirming Windows platform.
internal static class EnsureNativeMethods {
    private const uint TokenQuery = 0x0008;

    // TOKEN_INFORMATION_CLASS.TokenElevation = 20 (winnt.h)
    private const int TokenElevationClass = 20;

    [StructLayout(LayoutKind.Sequential)]
    private struct TokenElevationInfo {
        // Non-zero when the process token is elevated.
        public int TokenIsElevated;
    }

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool OpenProcessToken(
        IntPtr processHandle,
        uint desiredAccess,
        out IntPtr tokenHandle);

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetTokenInformation(
        IntPtr tokenHandle,
        int tokenInformationClass,
        out TokenElevationInfo tokenInformation,
        uint tokenInformationLength,
        out uint returnLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);

    // Returns true when the current process token is elevated (UAC-aware).
    // Uses TokenElevation rather than group-membership: correctly reflects
    // whether the token was elevated via UAC, not just whether the user
    // belongs to the Administrators group.
    internal static bool IsCurrentProcessElevated() {
        using var process = Process.GetCurrentProcess();

        if (!OpenProcessToken(process.Handle, TokenQuery, out var token)) {
            return false;
        }

        try {
            if (!GetTokenInformation(
                token,
                TokenElevationClass,
                out var info,
                (uint)Marshal.SizeOf(typeof(TokenElevationInfo)),
                out _)) {
                return false;
            }

            return info.TokenIsElevated != 0;
        } finally {
            CloseHandle(token);
        }
    }
}
