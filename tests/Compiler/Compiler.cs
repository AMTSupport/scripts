using Compiler;

[SetUpFixture]
[System.Diagnostics.CodeAnalysis.SuppressMessage(
    "Design",
    "CA1050:Declare types in namespaces",
    Justification = "Required for NUnit to run no matter the namespace."
)]
public class GlobalSetup
{
    [OneTimeSetUp]
    public static void Setup()
    {
        Program.SetupLogger(new Program.Options()
        {
            Verbosity = 3
        });
    }
}
