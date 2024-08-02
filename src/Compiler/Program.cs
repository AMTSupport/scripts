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

    internal static bool IsDebugging;

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
        [Option('v', "verbosity", FlagCounter = true, HelpText = "Set the verbosity level of the output.")]
        public int Verbosity { get; set; }

        [Option('q', "quiet", FlagCounter = true, HelpText = "Silence the Info output.")]
        public int Quiet { get; set; }

        [Option('i', "input", Required = true, HelpText = "Input file to be processed.")]
        public string? InputFile { get; set; }

        [Option('o', "output", Required = false, HelpText = "Output file to be written.")]
        public string? OutputFile { get; set; }

        [Option('f', "force", Required = false, HelpText = "Force overwrite of output file.")]
        public bool Force { get; set; }
    }

    public static void Main(string[] args)
    {
        var parser = new Parser(settings =>
        {
            settings.GetoptMode = true;
        });

        _ = parser.ParseArguments<Options>(args).WithParsed(opts =>
        {
            var logLevel = LogLevel.FromOrdinal(Math.Abs(opts.Quiet - opts.Verbosity + 2));
            IsDebugging = logLevel <= LogLevel.Debug;

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

                if (logLevel != LogLevel.Off) builder.ForLogger().FilterLevels(logLevel, LogLevel.Fatal).WriteTo(console);
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

                var printing = logLevel <= LogLevel.Debug ? e.ToString() : e.Message;
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

        var outputPath = Path.GetFullPath(options.OutputFile);
        if (!Directory.Exists(Path.GetDirectoryName(outputPath)))
        {
            Logger.Debug($"Creating directory {Path.GetDirectoryName(outputPath)}");
            Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
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
