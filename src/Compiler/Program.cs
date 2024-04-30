using CommandLine;

class Program
{
    public class Options
    {
        [Option('v', "verbose", Required = false, HelpText = "Set output to verbose messages.")]
        public bool Verbose { get; set; }

        [Option('i', "input", Required = true, HelpText = "Input file to be processed.")]
        public string InputFile { get; set; }

        [Option('o', "output", Required = false, HelpText = "Output file to be written.")]
        public string? OutputFile { get; set; }

        [Option('f', "force", Required = false, HelpText = "Force overwrite of output file.")]
        public bool Force { get; set; }
    }

    public static void Main(string[] args)
    {
        Parser.Default.ParseArguments<Options>(args).WithParsed(o =>
        {
            Console.WriteLine($"Verbose: {o.Verbose}");
            Console.WriteLine($"Input file: {o.InputFile}");
            Console.WriteLine($"Output file: {o.OutputFile}");

            if (string.IsNullOrWhiteSpace(o.InputFile)) {
                Console.WriteLine("Input file is required");
                return;
            }

            var compiledContent = CompileScript(o.InputFile);
            OutputToFile(o, compiledContent);
        });
    }

    public static string CompileScript(string inputFile) {
        var script = File.ReadAllText(inputFile);
        var compiledScript = new CompiledScript(Path.GetFileNameWithoutExtension(inputFile), script.Split('\n'));

        compiledScript.ApplyRangeEdits();
        return compiledScript.GetContent();
    }

    public static void OutputToFile(Options options, string content)
    {
        if (string.IsNullOrWhiteSpace(options.OutputFile)) {
            // Output to console to allow for piping
            Console.WriteLine(content);
            return;
        }

        // Output to file
        if (File.Exists(options.OutputFile)) {
            Console.WriteLine("Output file already exists");

            var removeFile = options.Force;
            if (!removeFile) {
                Console.WriteLine($"File {options.OutputFile} already exists. Overwrite? (Y/n)");
                var response = Console.ReadLine();
                removeFile = String.IsNullOrWhiteSpace(response) || response.Equals("y", StringComparison.CurrentCultureIgnoreCase);
            }

            if (removeFile) {
                Console.WriteLine("Removing file");
                File.Delete(options.OutputFile);
            }
        }

        Console.WriteLine($"Writing to file {options.OutputFile}");
        File.Create(options.OutputFile);
        File.WriteAllText(options.OutputFile, content);
    }
}
