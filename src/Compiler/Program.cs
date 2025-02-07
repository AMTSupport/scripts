// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

global using LanguageExt.Common;
global using static LanguageExt.Prelude;
global using LanguageExt.Pipes;

using C = System.Collections.Generic;
using System.Collections.Concurrent;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Language;
using System.Management.Automation.Runspaces;
using System.Text;
using CommandLine;
using Compiler.Analyser;
using Compiler.Module.Resolvable;
using Compiler.Requirements;
using NLog;
using NLog.Targets;
using System.Globalization;
using Extended.Collections.Generic;
using NuGet.Packaging;
using LanguageExt;
using System.Reflection;
using System.Diagnostics.Contracts;
using System.Diagnostics.CodeAnalysis;

namespace Compiler;

public class Program {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    internal static bool IsDebugging;

    internal static readonly ConcurrentBag<LanguageExt.Common.Error> Errors = [];

    public static readonly Lazy<RunspacePool> RunspacePool = new(() => {
        var sessionState = InitialSessionState.CreateDefault();
        sessionState.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
        sessionState.ImportPSModule(["Microsoft.PowerShell.PSResourceGet"]);

        var rsPool = RunspaceFactory.CreateRunspacePool(sessionState);
        rsPool.SetMinRunspaces(1);
        rsPool.SetMaxRunspaces(10);
        rsPool.Open();
        return rsPool;
    });

    public class Options {
        [Option('v', "verbosity", FlagCounter = true, HelpText = "Set the verbosity level of the output.")]
        public int Verbosity { get; set; }

        [Option('q', "quiet", FlagCounter = true, HelpText = "Silence the Info output.")]
        public int Quiet { get; set; }

        [Option('i', "input", Required = true, HelpText = "Input file or directory to be processed.")]
        public string? Input { get; set; }

        [Option('o', "output", Required = false, HelpText = "Output file to be written.")]
        public string? Output { get; set; }

        [Option('f', "force", Required = false, HelpText = "Force overwrite of output file.")]
        public bool Force { get; set; }
    }

    private static async Task<int> Main(string[] args) {
        var parser = new CommandLine.Parser(settings => settings.GetoptMode = true);

        var result = await parser.ParseArguments<Options>(args).MapResult(
            async opts => {
                CleanInput(opts);
                IsDebugging = SetupLogger(opts) <= LogLevel.Debug;

                if (GetFilesToCompile(opts.Input!).IsErr(out var error, out var filesToCompile)) {
                    Errors.Add(error);
                    return 1;
                }

                EnsureDirectoryStructure(opts.Input!, opts.Output, filesToCompile);

                var superParent = new ResolvableParent(opts.Input!);

                var sourceRoot = File.Exists(opts.Input) ? Path.GetDirectoryName(opts.Input)! : opts.Input;
                filesToCompile.ToList().ForEach(async scriptPath => {
                    var pathedModuleSpec = new PathedModuleSpec(sourceRoot, Path.GetFullPath(scriptPath));
                    if ((await Resolvable.TryCreateScript(pathedModuleSpec, superParent)).IsErr(out var error, out var resolvableScript)) {
                        Errors.Add(error.Enrich(pathedModuleSpec));
                        return;
                    }

                    superParent.QueueResolve(resolvableScript, compiled => {
                        Output(
                            sourceRoot,
                            opts.Output,
                            scriptPath,
                            compiled.GetPowerShellObject(),
                            opts.Force);
                    });
                });

                try {
                    await superParent.StartCompilation();
                } catch (Exception err) {
                    Errors.Add(err);
                }

                Logger.Trace("Finished compilation.");

                await OutputErrors(Errors, sourceRoot, opts.Output);

                return 1;
            },
#pragma warning disable CS1998
            async errors => {
#pragma warning restore CS1998
                Console.Error.WriteLine("There was an error parsing the command line arguments.");
                foreach (var err in errors) {
                    Console.Error.WriteLine(err);
                }
                errors.Output();

                return 1;
            }
        );

        RunspacePool.Value.Close();
        RunspacePool.Value.Dispose();
        LogManager.Shutdown();

        return result != 0 ? result : Errors.IsEmpty ? 0 : 1;
    }

    public static void CleanInput(Options opts) {
        ArgumentException.ThrowIfNullOrWhiteSpace(opts.Input, nameof(opts.Input));

        opts.Input = Path.GetFullPath(opts.Input!.Trim());
        if (opts.Output != null) {
            opts.Output = Path.GetFullPath(opts.Output.Trim());
            if (File.Exists(opts.Output)) {
                Logger.Error("Output must be a directory.");
                Environment.Exit(1);
            }
        }
    }

    public static LogLevel SetupLogger(Options opts) {
        var logLevel = LogLevel.FromOrdinal(Math.Abs(Math.Min(opts.Quiet, 3) - Math.Min(opts.Verbosity, 2) + 2));
        LogManager.Setup().LoadConfiguration(builder => {
            var layout = "${pad:padding=5:inner=${level:uppercase=true}}|${message}";
            if (logLevel <= LogLevel.Debug) layout = "[${threadid}] " + layout;

            var console = new ColoredConsoleTarget("console") {
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
                    new ConsoleWordHighlightingRule {
                        Regex = "\\b(?:error|exception|fail|fatal|warn|warning)\\b",
                        ForegroundColor = ConsoleOutputColor.DarkRed
                    },
                    new ConsoleWordHighlightingRule {
                        Regex = "\\b(?:info|log|message|success)\\b",
                        ForegroundColor = ConsoleOutputColor.Green
                    },
                    new ConsoleWordHighlightingRule {
                        Regex = "\\b(?:debug)\\b",
                        ForegroundColor = ConsoleOutputColor.Blue
                    },
                    new ConsoleWordHighlightingRule {
                        Regex = "\\b(?:trace)\\b",
                        ForegroundColor = ConsoleOutputColor.Gray
                    }
                }
            };

            var errorConsole = new ColoredConsoleTarget("errorConsole") {
                Layout = layout,
                DetectConsoleAvailable = console.DetectConsoleAvailable,
                EnableAnsiOutput = console.EnableAnsiOutput,
                StdErr = true,
                RowHighlightingRules = {
                    new ConsoleRowHighlightingRule {
                        Condition = "level == LogLevel.Fatal",
                        ForegroundColor = ConsoleOutputColor.Red
                    },
                    new ConsoleRowHighlightingRule {
                        Condition = "level == LogLevel.Error",
                        ForegroundColor = ConsoleOutputColor.DarkRed
                    },
                }
            };

            if (logLevel != LogLevel.Off) {
                if (logLevel <= LogLevel.Fatal) {
                    builder.ForLogger()
                        .FilterLevels(LogLevel.FromOrdinal(Math.Max(logLevel.Ordinal, LogLevel.Error.Ordinal)), LogLevel.Fatal)
                        .WriteTo(errorConsole);
                }

                if (logLevel <= LogLevel.Warn) {
                    builder.ForLogger()
                        .FilterLevels(logLevel, LogLevel.FromOrdinal(Math.Max(logLevel.Ordinal, LogLevel.Warn.Ordinal)))
                        .WriteTo(console);
                }
            }
        });

        return logLevel;
    }

    public static string GetOutputLocation(
        string sourceDirectory,
        string outputDirectory,
        string targetFile) {
        if (sourceDirectory == targetFile) return Path.Combine(outputDirectory, Path.GetFileName(targetFile));

        var relativePath = Path.GetRelativePath(sourceDirectory, targetFile);
        return Path.Combine(outputDirectory, relativePath);
    }

    /// <summary>
    /// Gets the files to compile from the input.
    ///
    /// Ignores files that are not .ps1 files,
    /// or files with the first line starting with #!ignore (case insensitive) or is empty.
    /// </summary>
    /// <param name="input">
    /// The input file or directory to get the files from,
    /// if it is a file, it will return a list with that file.
    ///
    /// Otherwise, it will return all .ps1 files in the recursed directory.
    /// </param>
    /// <returns>
    /// The valid files to compile.
    /// </returns>
    public static Fin<IEnumerable<string>> GetFilesToCompile(string input) {
        var files = new List<string>();
        if (File.Exists(input)) {
            if (!input.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase)) return InvalidInputError.InvalidFileType(input, ".ps1");
            files.Add(input);
        } else if (Directory.Exists(input)) {
            foreach (var file in Directory.EnumerateFiles(input, "*.ps1", SearchOption.AllDirectories)) {
                files.Add(file);
            }
        } else {
            return LanguageExt.Common.Error.New(new FileNotFoundException($"Input {input} is not a file or directory"));
        }

        files.RemoveAll(static file => {
            using var reader = new StreamReader(file);
            return reader.ReadLine()?.StartsWith("#!ignore", StringComparison.OrdinalIgnoreCase) ?? true;
        });

        return files;
    }

    /// <summary>
    /// Ensures that the output directory structure is the same as the source directory.
    /// </summary>
    /// <param name="sourceDirectory">
    /// The root directory of the source files.
    /// </param>
    /// <param name="outputDirectory">
    /// The root directory of the output files.
    /// </param>
    /// <param name="scripts">
    /// A list of the scripts that the output directory should contain.
    /// </param>
    public static void EnsureDirectoryStructure(
        string sourceDirectory,
        string? outputDirectory,
        IEnumerable<string> scripts
    ) {
        if (string.IsNullOrWhiteSpace(outputDirectory)) return;

        if (!Directory.Exists(outputDirectory)) Directory.CreateDirectory(outputDirectory);
        if (!Directory.Exists(sourceDirectory)) return;

        foreach (var script in scripts) {
            var outputDir = Path.GetDirectoryName(GetOutputLocation(sourceDirectory, outputDirectory, script));
            if (!Directory.Exists(outputDir)) Directory.CreateDirectory(outputDir!);
        }
    }

    public static async void Output(
        string sourceDirectory,
        string? outputDirectory,
        string fileName,
        string content,
        bool forceOverwrite
    ) {
        if (string.IsNullOrWhiteSpace(outputDirectory)) {
            // Output to console to allow for piping
            Console.Out.Write(content);
            return;
        }

        var outputPath = GetOutputLocation(sourceDirectory, outputDirectory, fileName);
        if (File.Exists(outputPath)) {
            var removeFile = forceOverwrite;
            if (!removeFile) {
                Logger.Info($"File {outputPath} already exists. Overwrite? (Y/n)");
                var response = Console.ReadLine();
                removeFile = string.IsNullOrWhiteSpace(response) || response.Equals("y", StringComparison.OrdinalIgnoreCase);
            }

            if (removeFile) {
                Logger.Trace("Removing file");

                try {
                    File.Delete(outputPath);
                } catch (IOException err) {
                    Errors.Add(LanguageExt.Common.Error.New("Unable to delete file", (Exception)err));
                    return;
                }
            } else {
                Logger.Trace("Skipping file");
                return;
            }
        }

        Logger.Trace($"Writing to file {outputPath}");
        using var fileStream = File.Open(outputPath, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        var encoder = new UTF8Encoding(true);
        fileStream.Write(encoder.GetPreamble(), 0, encoder.GetPreamble().Length);
        await fileStream.WriteAsync(encoder.GetBytes(content));
    }

    public static async Task<int> OutputErrors(
        IEnumerable<LanguageExt.Common.Error> errors,
        string sourceDirectory,
        Option<string> outputDirectory
    ) {
        // Wait for all threads to finish before outputting errors, this is to ensure all errors are captured.
        do {
            Logger.Debug($$"""
            Waiting for all threads to finish {
                Pending: {{ThreadPool.PendingWorkItemCount}}
                Threads: {{ThreadPool.ThreadCount}}
                Runspaces: {{Math.Abs(RunspacePool.Value.GetAvailableRunspaces() - RunspacePool.Value.GetMaxRunspaces())}} of {{RunspacePool.Value.GetMaxRunspaces()}}
            }
            """);
            await Task.Delay(25);
        } while (ThreadPool.PendingWorkItemCount != 0 && ThreadPool.ThreadCount > RunspacePool.Value.GetMaxRunspaces());


        if (Errors.IsEmpty) return 0;

        // Deduplicate errors.
        var errorSet = new C.HashSet<LanguageExt.Common.Error>();
        foreach (var error in errors) {
            if (errorSet.Contains(error)) continue;
            errorSet.Add(error);
        }

        // Seriously .NET, why is there no fucking double ended queue.
        var printedBefore = false; // This is to prevent a newline before the first error
        var errorQueue = new Deque<LanguageExt.Common.Error>();
        errorQueue.AddRange(errorSet);
        var outputDebuggables = new Dictionary<byte[], string>();
        do {
            var err = errorQueue.PopFirst();

            if (IsDebugging && outputDirectory.IsSome(out var outDir)
                && err is WrappedErrorWithDebuggableContent wrappedDebuggable
                && wrappedDebuggable.Module.IsSome(out var module)
                && module is PathedModuleSpec pathedModuleSpec
                && !outputDebuggables.ContainsKey(module.Hash)
            ) {
                // We could be outputting a psm1 which would not have its structure copied
                // Lets make sure its output path is created.
                var outputParent = Directory.GetParent(GetOutputLocation(sourceDirectory, outDir, pathedModuleSpec.FullPath))!;
                if (!outputParent.Exists) outputParent.Create();

                Output(
                    sourceDirectory,
                    outDir,
                    pathedModuleSpec.FullPath,
                    wrappedDebuggable.Content,
                    true
                );

                outputDebuggables.Add(module.Hash, Path.GetRelativePath(sourceDirectory, pathedModuleSpec.FullPath));
            }

            if (err is WrappedErrorWithDebuggableContent wrappedErr) {
                errorQueue.PushFirst(wrappedErr.InnerException);
                continue;
            }

            // Flatten ManyErrors into the indiviuals
            if (err is ManyErrors manyErrors && manyErrors.Count > 0) {
                errorQueue.PushRangeFirst(manyErrors.Errors);
                continue;
            }

            var type = err.IsExceptional ? LogLevel.Error : LogLevel.Warn;

            if (printedBefore) {
                if (type == LogLevel.Error) {
                    Console.Error.WriteLine();
                } else {
                    Console.WriteLine();
                }
            } else {
                printedBefore = true;
            }

            var message = err switch {
                Issue => err.ToString(),
                _ => err.Message + (IsDebugging
                    ? (err.Exception.IsSome(out var exception)
                        ? Environment.NewLine + exception.Message + Environment.NewLine + exception.StackTrace
                        : "")
                    : ""
                )
            };

            if (type == LogLevel.Error) {
                Console.Error.WriteLine(message);
            } else {
                Console.WriteLine(message);
            }
        } while (errorQueue.Count > 0);

        if (outputDebuggables.Count > 0) {
            Logger.Error($"""
            Encountered ${outputDebuggables.Count} files with errors while compiling, the debuggable content has been output to the following files:
            {string.Join("\n", outputDebuggables.Select(kv => $"\t{kv.Value}"))}
            """);
        }

        return 1;
    }

    internal static PowerShell GetPowerShellSession() {
        var pwsh = PowerShell.Create(RunspacePool.Value.InitialSessionState);
        pwsh.RunspacePool = RunspacePool.Value;
        return pwsh;
    }

    internal static Fin<Collection<PSObject>> RunPowerShell(string script, params object[] args) {
        var pwsh = GetPowerShellSession();
        pwsh.AddScript(script);
        args.ToList().ForEach(arg => pwsh.AddArgument(arg));

        var result = pwsh.Invoke();

        pwsh.Streams.Verbose.ToList().ForEach(log => Logger.Debug(log.Message));
        pwsh.Streams.Debug.ToList().ForEach(log => Logger.Debug(log.Message));
        pwsh.Streams.Information.ToList().ForEach(log => Logger.Info(CultureInfo.CurrentCulture, log.MessageData));
        pwsh.Streams.Warning.ToList().ForEach(log => Logger.Warn(log.Message));

        if (pwsh.HadErrors) {
            var ast = AstHelper.GetAstReportingErrors(script, None, ["ModuleNotFoundDuringParse"], out _).Match(
                ast => ast,
                error => {
                    Logger.Error("Unable to parse ast of script for error reporting.");
                    throw error;
                }
            );

            var errors = pwsh.Streams.Error.Select(log => {
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
                var extent = new ScriptExtent(startPosition, endPosition);

                return Issue.Error(errorMessage, extent, ast);
            });

            return FinFail<Collection<PSObject>>(LanguageExt.Common.Error.Many(errors.ToArray()));
        }

        return FinSucc(result);
    }

    /// <summary>
    /// Gets the embedded resource from the assembly inside the Resource folder.
    /// </summary>
    /// <param name="resourceName">
    /// The path of the resource without the assembly name or Resource folder, e.g. "ExtraModuleInfo.ModuleName.json"
    /// Folders must separated by '.' instead of '/'.
    /// </param>
    /// <returns>
    /// The stream of the embedded resource if one is found, otherwise None.
    /// It is the caller's responsibility to dispose of the stream.
    /// </returns>
    [Pure]
    [return: NotNull]
    internal static Option<Stream> GetEmbeddedResource(string resourceName) {
        var assemblyName = Assembly.GetExecutingAssembly().GetName();
        var resourcePath = $"{assemblyName.Name}.Resources.{resourceName}";
        var templateStream = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourcePath);

        return templateStream;
    }
}
