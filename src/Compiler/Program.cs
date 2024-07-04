using System.Text;
using CommandLine;
using Compiler;
using NLog;

class Program
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public class Options
    {
        [Option('v', "verbose", Required = false, HelpText = "Set output to verbose messages.")]
        public bool Verbose { get; set; }

        [Option('i', "input", Required = true, HelpText = "Input file to be processed.")]
        public string? InputFile { get; set; }

        [Option('o', "output", Required = false, HelpText = "Output file to be written.")]
        public string? OutputFile { get; set; }

        [Option('f', "force", Required = false, HelpText = "Force overwrite of output file.")]
        public bool Force { get; set; }
    }

    public static void Main(string[] args)
    {
        Parser.Default.ParseArguments<Options>(args).WithParsed(o =>
        {
            LogManager.Setup().LoadConfiguration(builder =>
            {
                builder.ForLogger()
                    .FilterLevels(LogLevel.Trace, LogLevel.Error)
                    .WriteToColoredConsole(
                        "${pad:padding=5:inner=${level:uppercase=true}}|${message}",
                        true,
                        detectConsoleAvailable: true,
                        enableAnsiOutput: true
                    );
            });

            var compiledScript = new CompiledScript(Path.GetFullPath(o.InputFile!));
            var compiledContent = compiledScript.Compile();
            OutputToFile(o, compiledContent);
        });
    }

    public static async void OutputToFile(Options options, string content)
    {
        if (string.IsNullOrWhiteSpace(options.OutputFile))
        {
            // Output to console to allow for piping
            Console.OpenStandardOutput().Write(Encoding.UTF8.GetBytes(content));
            return;
        }

        // Output to file
        if (File.Exists(options.OutputFile))
        {
            Logger.Info("Output file already exists");

            var removeFile = options.Force;
            if (!removeFile)
            {
                Logger.Info($"File {options.OutputFile} already exists. Overwrite? (Y/n)");
                var response = Console.ReadLine();
                removeFile = string.IsNullOrWhiteSpace(response) || response.Equals("y", StringComparison.CurrentCultureIgnoreCase);
            }

            if (removeFile)
            {
                Logger.Trace("Removing file");
                File.Delete(options.OutputFile);
            }
        }

        Logger.Info($"Writing to file {options.OutputFile}");
        var fileStream = File.Open(options.OutputFile, FileMode.CreateNew, FileAccess.Write, FileShare.ReadWrite);
        await fileStream.WriteAsync(Encoding.UTF8.GetBytes(content));
        fileStream.Close();
    }
}
