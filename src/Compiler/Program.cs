using System.Collections.Concurrent;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text;
using CommandLine;
using Compiler.Analyser;
using Compiler.Module.Compiled;
using Compiler.Module.Resolvable;
using Compiler.Requirements;
using NLog;
using NLog.Targets;

class Program
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    internal static bool IsDebugging;

    internal static readonly ConcurrentBag<Issue> Issues = [];

    internal static readonly CancellationTokenSource CancelSource = new();

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

        [Option('i', "input", Required = true, HelpText = "Input file or directory to be processed.")]
        public string? Input { get; set; }

        [Option('o', "output", Required = false, HelpText = "Output file to be written.")]
        public string? Output { get; set; }

        [Option("fail-fast", Required = false, HelpText = "Fail fast on error.")]
        public bool FailFast { get; set; }

        [Option('f', "force", Required = false, HelpText = "Force overwrite of output file.")]
        public bool Force { get; set; }
    }

    public static void Main(string[] args)
    {
        var parser = new Parser(settings =>
        {
            settings.GetoptMode = true;
        });


        _ = parser.ParseArguments<Options>(args).WithParsed(async opts =>
        {
            CleanInput(opts);
            IsDebugging = SetupLogger(opts) <= LogLevel.Debug;

            ConcurrentBag<(string, Exception)> compilerErrors = [];
            // TODO - Super parent, Submit completed scripts so they can be resolved by other scripts
            CancelSource.Token.Register(() => Logger.Error("Compilation was cancelled."));
            var compilerTask = Parallel.ForEachAsync(
                GetFilesToCompile(opts.Input!),
                CancelSource.Token,
                async (script, ct) =>
                {
                    var compiledScript = await CompileScript(script, compilerErrors, ct);
                    if (compiledScript == null && opts.FailFast) { CancelSource.Cancel(); }
                    if (compiledScript == null) return;
                    OutputToFile(
                        opts.Output,
                        Path.ChangeExtension(compiledScript.ModuleSpec.Name, "ps1"),
                        compiledScript.GetPowerShellObject(),
                        opts.Force
                    );
                    Logger.Debug($"Compiled {script}");
                }
            );

            do
            {
                if (compilerTask.Status == TaskStatus.Canceled || compilerTask.Status == TaskStatus.Canceled || !compilerErrors.IsEmpty)
                {
                    await CancelSource.CancelAsync();
                    LogManager.Flush();

                    Logger.Error("There was an error compiling the script, please see the errors below:");
                    if (compilerTask.Exception != null)
                    {
                        Logger.Error(compilerTask.Exception.Message);
                    }

                    foreach (var (scriptPath, e) in compilerErrors)
                    {
                        Logger.Error($"Error compiling script {scriptPath}");
                        var printing = IsDebugging ? e.ToString() : e.Message;
                        Logger.Error(printing);
                    }

                    break;
                }

                Task.Delay(25).Wait();
            } while (compilerTask.Status != TaskStatus.RanToCompletion);
        }).WithNotParsed(errors =>
        {
            Console.Error.WriteLine("There was an error parsing the command line arguments.");
            foreach (var err in errors)
            {
                Console.Error.WriteLine(err);
            }
            errors.Output();
            Environment.Exit(1);
        });

        if (!Issues.IsEmpty)
        {
            Logger.Warn("There were issues found by the analyser during compilation.");
            Issues.ToList().ForEach(issue => issue.Print());
        }

        Environment.Exit(0);
    }

    public static async Task<CompiledScript?> CompileScript(string scriptPath, ConcurrentBag<(string, Exception)> compilerErrors, CancellationToken ct) => await Task.Run(() =>
    {
        var pathedModuleSpec = new PathedModuleSpec(Path.GetFullPath(scriptPath));
        var resolvableScript = new ResolvableScript(pathedModuleSpec);

        try
        {
            return (CompiledScript)resolvableScript.IntoCompiled();
        }
        catch (Exception e)
        {
            lock (compilerErrors) { compilerErrors.Add((scriptPath, e)); }
            return null;
        }
    }, ct);

    public static void CleanInput(Options opts)
    {
        opts.Input = Path.GetFullPath(opts.Input!.Trim());

        if (opts.Output != null)
        {
            opts.Output = Path.GetFullPath(opts.Output.Trim());
            if (File.Exists(opts.Output))
            {
                Logger.Error("Output must be a directory.");
                Environment.Exit(1);
            }
        }
    }

    public static IEnumerable<string> GetFilesToCompile(string input)
    {
        if (File.Exists(input))
        {
            yield return input;
        }
        else if (Directory.Exists(input))
        {
            foreach (var file in Directory.EnumerateFiles(input, "*.ps1", SearchOption.AllDirectories))
            {
                yield return file;
            }
        }
        else
        {
            Logger.Error("Input must be a file or directory.");
            Environment.Exit(1);
        }
    }

    public static LogLevel SetupLogger(Options opts)
    {
        var logLevel = LogLevel.FromOrdinal(Math.Abs(Math.Min(opts.Quiet, 3) - Math.Min(opts.Verbosity, 2) + 2));
        LogManager.Setup().LoadConfiguration(builder =>
        {
            var layout = "${pad:padding=5:inner=${level:uppercase=true}}|${message}";
            if (logLevel <= LogLevel.Debug) layout = "[${threadid}] " + layout;

            var console = new ColoredConsoleTarget("console")
            {
                Layout = layout,
                DetectConsoleAvailable = true,
                EnableAnsiOutput = true,
                RowHighlightingRules = {
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

            var errorConsole = new ColoredConsoleTarget("errorConsole")
            {
                Layout = layout,
                DetectConsoleAvailable = console.DetectConsoleAvailable,
                EnableAnsiOutput = console.EnableAnsiOutput,
                StdErr = true,
                RowHighlightingRules = {
                    new ConsoleRowHighlightingRule
                    {
                        Condition = "level == LogLevel.Fatal",
                        ForegroundColor = ConsoleOutputColor.Red
                    },
                    new ConsoleRowHighlightingRule
                    {
                        Condition = "level == LogLevel.Error",
                        ForegroundColor = ConsoleOutputColor.DarkRed
                    },
                }
            };

            if (logLevel != LogLevel.Off)
            {
                if (logLevel <= LogLevel.Fatal) builder.ForLogger().FilterLevels(LogLevel.FromOrdinal(Math.Max(logLevel.Ordinal, LogLevel.Error.Ordinal)), LogLevel.Fatal).WriteTo(errorConsole);
                if (logLevel <= LogLevel.Warn) builder.ForLogger().FilterLevels(logLevel, LogLevel.FromOrdinal(Math.Max(logLevel.Ordinal, LogLevel.Warn.Ordinal))).WriteTo(console);
            }
        });

        return logLevel;
    }

    public static async void OutputToFile(
        string? directory,
        string fileName,
        string content,
        bool overwrite)
    {
        if (string.IsNullOrWhiteSpace(directory))
        {
            // Output to console to allow for piping
            Console.OpenStandardOutput().Write(Encoding.UTF8.GetBytes(content));
            return;
        }

        var output = Path.Combine(directory, fileName);
        if (File.Exists(output))
        {
            var removeFile = overwrite;
            if (!removeFile)
            {
                Logger.Info($"File {output} already exists. Overwrite? (Y/n)");
                var response = Console.ReadLine();
                removeFile = string.IsNullOrWhiteSpace(response) || response.Equals("y", StringComparison.CurrentCultureIgnoreCase);
            }

            if (removeFile)
            {
                Logger.Trace("Removing file");
                File.Delete(output);
            }
        }

        Logger.Info($"Writing to file {output}");
        using var fileStream = File.Open(output, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        await fileStream.WriteAsync(Encoding.UTF8.GetBytes(content));
    }

    internal static PowerShell GetPowerShellSession()
    {
        var pwsh = PowerShell.Create(RunspacePool.Value.InitialSessionState);
        pwsh.RunspacePool = RunspacePool.Value;
        return pwsh;
    }

    internal static Collection<PSObject> RunPowerShell(string script)
    {
        var pwsh = GetPowerShellSession();
        pwsh.AddScript(script);
        return pwsh.Invoke();
    }

    ~Program()
    {
        RunspacePool.Value.Close();
        RunspacePool.Value.Dispose();
        LogManager.Shutdown();
    }
}
