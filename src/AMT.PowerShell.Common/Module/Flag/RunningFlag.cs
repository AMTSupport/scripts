namespace AMT.PowerShell.Common.Module;

using System;
using System.Diagnostics;
using System.Globalization;
using System.Reflection;
using System.Management.Automation.Runspaces;

public sealed class RunningFlag : Flag {
    private const string IgnoredDataWarning = "Data is ignored for RunningFlag, only the PID of the running process is stored.";

    internal static Action<string>? WarningWriterOverride { get; set; }

    public RunningFlag() : base("running") {
    }

    public override void Set(object? data) {
        if (data is not null) {
            EmitIgnoredDataWarning();
        }

        var currentPid = Process.GetCurrentProcess().Id;
        base.Set(currentPid.ToString(CultureInfo.InvariantCulture));
    }

    public bool IsRunning() {
        if (!this.Exists()) {
            return false;
        }

        var data = this.GetData()?.ToString();
        if (!int.TryParse(data, NumberStyles.Integer, CultureInfo.InvariantCulture, out var processId)) {
            this.Remove();
            return false;
        }

        if (!IsProcessRunning(processId)) {
            this.Remove();
            return false;
        }

        return true;
    }

    private static void EmitIgnoredDataWarning() {
        var warningWriter = WarningWriterOverride;
        if (warningWriter is not null) {
            warningWriter(IgnoredDataWarning);
            return;
        }

        if (TryWriteHostWarning(IgnoredDataWarning)) {
            return;
        }

        Trace.TraceWarning(IgnoredDataWarning);
    }

    private static bool TryWriteHostWarning(string message) {
        try {
            var defaultRunspace = Runspace.DefaultRunspace;
            if (defaultRunspace is null) {
                return false;
            }

            var hostProperty = defaultRunspace.GetType().GetProperty("Host", BindingFlags.Public | BindingFlags.Instance);
            var host = hostProperty?.GetValue(defaultRunspace, null);
            if (host is null) {
                return false;
            }

            var uiProperty = host.GetType().GetProperty("UI", BindingFlags.Public | BindingFlags.Instance);
            var ui = uiProperty?.GetValue(host, null);
            if (ui is null) {
                return false;
            }

            var writeWarningMethod = ui.GetType().GetMethod("WriteWarningLine", new[] { typeof(string) });
            if (writeWarningMethod is null) {
                return false;
            }

            writeWarningMethod.Invoke(ui, new object[] { message });
            return true;
        } catch (TargetInvocationException) {
            return false;
        } catch (TargetException) {
            return false;
        } catch (MethodAccessException) {
            return false;
        } catch (MemberAccessException) {
            return false;
        } catch (InvalidOperationException) {
            return false;
        } catch (NotSupportedException) {
            return false;
        }
    }

    private static bool IsProcessRunning(int processId) {
        try {
            using var process = Process.GetProcessById(processId);
            return !process.HasExited;
        } catch (ArgumentException) {
            return false;
        } catch (InvalidOperationException) {
            return false;
        } catch (NotSupportedException) {
            return false;
        }
    }
}
