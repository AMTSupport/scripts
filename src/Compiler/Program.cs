using System.Management.Automation.Runspaces;
using System.Text;
using CommandLine;
using Compiler;
using NLog;
using NLog.Targets;

class Program
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public static readonly Lazy<RunspacePool> RunspacePool = new(() =>
    {
        var sessionState = InitialSessionState.CreateDefault2();
        sessionState.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
        sessionState.ImportPSModule(new[] { "Microsoft.PowerShell.PSResourceGet" });

        var rsPool = RunspaceFactory.CreateRunspacePool(sessionState);
        rsPool.SetMinRunspaces(1);
        rsPool.SetMaxRunspaces(5);
        rsPool.Open();
        return rsPool;
    });

    public class Options
    {
        [Option('v', "verbose", Required = false, HelpText = "Set output to verbose messages.")]
        public bool Verbose { get; set; }

        [Option('d', "debug", Required = false, HelpText = "Set output to debug messages.")]
        public bool Debug { get; set; }

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
                var console = new ColoredConsoleTarget("console")
                {
                    Layout = "${pad:padding=5:inner=${level:uppercase=true}}|${message}",
                    DetectConsoleAvailable = true,
                    EnableAnsiOutput = true,
                    RowHighlightingRules = {
                        new() {
                            Condition = "level == LogLevel.Fatal",
                            ForegroundColor = ConsoleOutputColor.Red,
                        },
                        new() {
                            Condition = "level == LogLevel.Error",
                            ForegroundColor = ConsoleOutputColor.DarkRed
                        },
                        new() {
                            Condition = "level == LogLevel.Warn",
                            ForegroundColor = ConsoleOutputColor.Yellow
                        },
                        new() {
                            Condition = "level == LogLevel.Info",
                            ForegroundColor = ConsoleOutputColor.Gray
                        },
                        new() {
                            Condition = "level == LogLevel.Debug",
                            ForegroundColor = ConsoleOutputColor.DarkMagenta
                        },
                        new() {
                            Condition = "level == LogLevel.Trace",
                            ForegroundColor = ConsoleOutputColor.DarkGray
                        }
                    },
                    WordHighlightingRules = {
                        new ConsoleWordHighlightingRule
                        {
                            Regex = "\\b(?:error|exception|fail|fatal|warn|warning)\\b",
                            ForegroundColor = ConsoleOutputColor.DarkRed
                        },
                        new ConsoleWordHighlightingRule
                        {
                            Regex = "\\b(?:info|log|message|success)\\b",
                            ForegroundColor = ConsoleOutputColor.Green
                        },
                        new ConsoleWordHighlightingRule
                        {
                            Regex = "\\b(?:debug)\\b",
                            ForegroundColor = ConsoleOutputColor.Blue
                        },
                        new ConsoleWordHighlightingRule
                        {
                            Regex = "\\b(?:trace)\\b",
                            ForegroundColor = ConsoleOutputColor.Gray
                        }
                    }
                };

                builder.ForLogger().FilterLevels(LogLevel.Info, LogLevel.Fatal).WriteTo(console);
                if (o.Verbose) builder.ForLogger().FilterLevel(LogLevel.Trace).WriteTo(console);
                if (o.Debug) builder.ForLogger().FilterLevel(LogLevel.Debug).WriteTo(console);
            });

            var compiledContent = string.Empty;
            try
            {
                var compiledScript = new CompiledScript(Path.GetFullPath(o.InputFile!));
                compiledContent = compiledScript.Compile();
            }
            catch (Exception e)
            {
                Logger.Error("There was an error compiling the script, please see the error below:");

                var printing = o.Verbose == true ? e.ToString() : e.Message;
                Logger.Error(printing);

                Environment.Exit(1);
            }

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
