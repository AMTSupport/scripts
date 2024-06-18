using System.Management.Automation;
using System.Management.Automation.Runspaces;
using Compiler.Requirements;
using NLog;

namespace Compiler.Module;

public class RemoteModule(ModuleSpec moduleSpec, byte[] bytes) : Module(moduleSpec)
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    public byte[] BytesZip = bytes;

    /*
        Create a new module that is hosted on the PowerShell Gallery.
    */
    public static RemoteModule FromModuleRequirement(ModuleSpec moduleSpec)
    {
        // Obtain a variable which contains the binary zip file of the module.
        // Compress the binary zip into a string that we can store in the powershell script.
        // This will later be extracted and imported into the script.

        var binaryZip = GetBinaryZip(moduleSpec);
        return new RemoteModule(moduleSpec, binaryZip);
    }

    public override ModuleMatch GetModuleMatchFor(ModuleSpec requirement)
    {
        return ModuleSpec.CompareTo(requirement);
    }

    public override string GetContent(int indent = 0)
    {
        return $"'{Convert.ToBase64String(BytesZip)}'";
    }

    // TODO - Run all of these in a single session to reduce overhead.
    private static byte[] GetBinaryZip(ModuleSpec moduleSpec)
    {
        var zipPath = Path.GetTempPath();
        var versionString = ConvertVersionParameters(moduleSpec.RequiredVersion?.ToString(), moduleSpec.MinimumVersion?.ToString(), moduleSpec.MaximumVersion?.ToString());
        var PowerShellCode = /*ps1*/ $$"""
        Install-Module 'Microsoft.PowerShell.PSResourceGet' -Scope CurrentUser -Confirm:$False -Force;
        Import-Module 'Microsoft.PowerShell.PSResourceGet' -Force;
        Set-PSResourceRepository -Name PSGallery -Trusted -Confirm:$False;

        try {
            $Module = Find-PSResource -Name '{{moduleSpec.Name}}' {{(versionString != null ? $"-Version '{versionString}'" : "")}};
        } catch {
            exit 10;
        }

        try {
            $Module | Save-PSResource -Path '{{zipPath}}' -AsNupkg;
        } catch {
            exit 11;
        }

        return $env:TEMP | Join-Path -ChildPath "{{moduleSpec.Name}}.$($Module.Version).nupkg";
        """;

        Logger.Debug("Running the following PowerShell code to download the module from the PowerShell Gallery:");
        Logger.Debug(PowerShellCode);

        var sessionState = InitialSessionState.CreateDefault2();
        sessionState.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
        sessionState.ImportPSModule(new[] { "Microsoft.PowerShell.PSResourceGet" });
        sessionState.LanguageMode = PSLanguageMode.FullLanguage;
        var runspace = RunspaceFactory.CreateRunspace(sessionState);
        runspace.Open();

        var ps = PowerShell.Create(runspace);
        ps.AddScript(PowerShellCode);
        var result = ps.Invoke();
        runspace.Close();

        if (ps.HadErrors)
        {
            throw new Exception($"Failed to download module {moduleSpec.Name} from the PowerShell Gallery. Error: {ps.Streams.Error[0].Exception.Message}");
        }

        zipPath = result.First().ToString();
        Logger.Debug($"Downloaded module {moduleSpec.Name} from the PowerShell Gallery to {zipPath}.");
        var bytesZip = File.ReadAllBytes(zipPath);
        File.Delete(zipPath);

        return bytesZip;
    }

    // Based on https://github.com/PowerShell/PowerShellGet/blob/c6aea39ea05491c648efd7aebdefab1ae7c5b213/src/PowerShellGet.psm1#L111-L144
    private static string? ConvertVersionParameters(
        string? requiredVersion,
        string? minimumVersion,
        string? maximumVersion) => (requiredVersion, minimumVersion, maximumVersion) switch
        {
            (null, null, null) => null,
            (string ver, null, null) => ver,
            (_, string min, null) => $"[{min},)",
            (_, null, string max) => $"(,{max}]",
            (_, string min, string max) => $"[{min},{max}]"
        };
}
