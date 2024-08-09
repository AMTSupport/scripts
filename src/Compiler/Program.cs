using System.Collections.Concurrent;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Language;
using System.Management.Automation.Runspaces;
using System.Text;
using CommandLine;
using Compiler.Analyser;
using Compiler.Module.Compiled;
using Compiler.Module.Resolvable;
using Compiler.Requirements;
using NLog;
using NLog.Targets;

namespace Compiler;

public class Program
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
        var parser = new CommandLine.Parser(settings =>
        {
            settings.GetoptMode = true;
        });


        _ = parser.ParseArguments<Options>(args).WithParsed(async opts =>
        {
            CleanInput(opts);
            IsDebugging = SetupLogger(opts) <= LogLevel.Debug;

            var filesToCompile = GetFilesToCompile(opts.Input!);
            EnsureDirectoryStructure(opts.Input!, opts.Output, filesToCompile);

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
                        opts.Input!,
                        opts.Output,
                        script,
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
        ArgumentException.ThrowIfNullOrWhiteSpace(opts.Input, nameof(opts.Input));

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

    public static string GetOutputLocation(
        string sourceDirectory,
        string outputDirectory,
        string targetFile)
    {
        if (sourceDirectory == targetFile) return Path.Combine(outputDirectory, Path.GetFileName(targetFile));

        var relativePath = Path.GetRelativePath(sourceDirectory, targetFile);
        return Path.Combine(outputDirectory, relativePath);
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

    public static void EnsureDirectoryStructure(
        string sourceDirectory,
        string? outputDirectory,
        IEnumerable<string> scripts
    )
    {
        if (string.IsNullOrWhiteSpace(outputDirectory)) return;

        if (!Directory.Exists(outputDirectory)) Directory.CreateDirectory(outputDirectory);
        if (!Directory.Exists(sourceDirectory)) return;

        foreach (var script in scripts)
        {
            var outputDir = Path.GetDirectoryName(GetOutputLocation(sourceDirectory, outputDirectory, script));
            if (!Directory.Exists(outputDir)) Directory.CreateDirectory(outputDir!);
        }
    }

    public static async void OutputToFile(
        string sourceDirectory,
        string? outputDirectory,
        string fileName,
        string content,
        bool overwrite)
    {
        if (string.IsNullOrWhiteSpace(outputDirectory))
        {
            // Output to console to allow for piping
            Console.OpenStandardOutput().Write(Encoding.UTF8.GetBytes(content));
            return;
        }

        var outputPath = GetOutputLocation(sourceDirectory, outputDirectory, fileName);
        if (File.Exists(outputPath))
        {
            var removeFile = overwrite;
            if (!removeFile)
            {
                Logger.Info($"File {outputPath} already exists. Overwrite? (Y/n)");
                var response = Console.ReadLine();
                removeFile = string.IsNullOrWhiteSpace(response) || response.Equals("y", StringComparison.CurrentCultureIgnoreCase);
            }

            if (removeFile)
            {
                Logger.Trace("Removing file");
                File.Delete(outputPath);
            }
        }

        Logger.Info($"Writing to file {outputPath}");
        using var fileStream = File.Open(outputPath, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        await fileStream.WriteAsync(Encoding.UTF8.GetBytes(content));
    }

    internal static PowerShell GetPowerShellSession()
    {
        var pwsh = PowerShell.Create(RunspacePool.Value.InitialSessionState);
        pwsh.RunspacePool = RunspacePool.Value;
        return pwsh;
    }

    internal static Collection<PSObject> RunPowerShell(string script, params object[] args)
    {
        var pwsh = GetPowerShellSession();
        pwsh.AddScript(script);
        args.ToList().ForEach(arg => pwsh.AddArgument(arg));

        var result = pwsh.Invoke();

        pwsh.Streams.Verbose.ToList().ForEach(log => Logger.Debug(log.Message));
        pwsh.Streams.Debug.ToList().ForEach(log => Logger.Debug(log.Message));
        pwsh.Streams.Information.ToList().ForEach(log => Logger.Info(log.MessageData));
        pwsh.Streams.Warning.ToList().ForEach(log => Logger.Warn(log.Message));

        if (pwsh.HadErrors)
        {
            var ast = AstHelper.GetAstReportingErrors(script, null, []);

            pwsh.Streams.Error.ToList().ForEach(log =>
            {
                Logger.Debug(log.InvocationInfo.ScriptLineNumber);
                Logger.Debug(log.InvocationInfo.OffsetInLine);
                Logger.Debug(log.InvocationInfo.Line);

                var startPosition = new ScriptPosition(
                    "In-Memory-Script",
                    log.InvocationInfo.ScriptLineNumber,
                    log.InvocationInfo.OffsetInLine,
                    log.InvocationInfo.Line
                );
                var endPosition = new ScriptPosition(
                    "In-Memory-Script",
                    log.InvocationInfo.ScriptLineNumber,
                    log.InvocationInfo.Line.Length,
                    log.InvocationInfo.Line
                );

                var errorMessage = log.ErrorDetails?.Message ?? log.Exception?.Message ?? log.FullyQualifiedErrorId;

                AstHelper.PrintPrettyAstError(
                    new ScriptExtent(startPosition, endPosition),
                    ast,
                    errorMessage
                );
            });
        }

        return result;
    }

    ~Program()
    {
        RunspacePool.Value.Close();
        RunspacePool.Value.Dispose();
        LogManager.Shutdown();
    }
}
