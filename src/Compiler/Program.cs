using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text;
using CommandLine;
using Compiler.Module.Resolvable;
using Compiler.Requirements;
using NLog;
using NLog.Targets;

class Program : IDisposable
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
        _ = Parser.Default.ParseArguments<Options>(args).WithParsed(opts =>
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
                if (opts.Verbose) builder.ForLogger().FilterLevel(LogLevel.Trace).WriteTo(console);
                if (opts.Debug) builder.ForLogger().FilterLevel(LogLevel.Debug).WriteTo(console);
            });

            var compiledContent = string.Empty;
            try
            {
                var pathedModuleSpec = new PathedModuleSpec(Path.GetFullPath(opts.InputFile!));
                var resolvableScript = new ResolvableScript(pathedModuleSpec);
                var compiledScript = resolvableScript.IntoCompiled();
                compiledContent = compiledScript.GetPowerShellObject();
            }
            catch (Exception e)
            {
                Logger.Error("There was an error compiling the script, please see the error below:");

                var printing = opts.Verbose == true ? e.ToString() : e.Message;
                Logger.Error(printing);

                Environment.Exit(1);
            }

            OutputToFile(opts, compiledContent);
        });

        LogManager.Shutdown();
        Environment.Exit(0);
    }

    public static void OutputToFile(Options options, string content)
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
        using var fileStream = File.Open(options.OutputFile, FileMode.CreateNew, FileAccess.Write, FileShare.ReadWrite);
        fileStream.Write(Encoding.UTF8.GetBytes(content));
    }

    internal static Collection<PSObject> RunPowerShell(string script)
    {
        var pwsh = PowerShell.Create(RunspaceMode.NewRunspace);
        pwsh.RunspacePool = RunspacePool.Value;
        pwsh.AddScript(script);
        return pwsh.Invoke();
    }

    public void Dispose()
    {
        throw new NotImplementedException();
    }
}
