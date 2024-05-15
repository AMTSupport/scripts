using Compiler.Requirements;

namespace Compiler.Module;

public class RemoteModule(string name, byte[] bytes) : Module(new ModuleSpec(name))
{
    public byte[] Bytes { get; } = bytes;

    /*
        Create a new module that is hosted on the PowerShell Gallery.
    */
    public static RemoteModule FromModuleRequirement(ModuleSpec requirement)
    {
        // Obtain a variable which contains the binary zip file of the module.
        // Compress the binary zip into a string that we can store in the powershell script.
        // This will later be extracted and imported into the script.

        var binaryZip = GetBinaryZip(requirement.Name);

        return new RemoteModule(requirement.Name, binaryZip);
    }

    public override ModuleMatch GetModuleMatchFor(ModuleSpec requirement)
    {
        throw new NotImplementedException();
    }

    public override string GetContent(int indent = 0)
    {
        // return the content as the zip files bytes encoded to a string
        throw new NotImplementedException();
    }

    private static byte[] GetBinaryZip(string name)
    {
        // TODO
        return [];
    }
}
