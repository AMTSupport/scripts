using System.Reflection;
using System.Text;
using CommandLine;
using Json.More;
using QuikGraph;
using QuikGraph.Graphviz;

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
            // Console.WriteLine($"Verbose: {o.Verbose}");
            // Console.WriteLine($"Input file: {o.InputFile}");
            // Console.WriteLine($"Output file: {o.OutputFile}");

            if (string.IsNullOrWhiteSpace(o.InputFile))
            {
                Console.WriteLine("Input file is required");
                return;
            }

            var compiledContent = CompileScript(o.InputFile);
            OutputToFile(o, compiledContent);
        });
    }

    public static string CompileScript(string inputFile)
    {
        var script = File.ReadAllText(inputFile);
        var compiledScript = new CompiledScript(Path.GetFileNameWithoutExtension(inputFile), script.Split('\n'));

        var graphViz = compiledScript.ModuleGraph.ToGraphviz();
        Console.WriteLine(graphViz);

        compiledScript.Document.ApplyRangeEdits();
        return compiledScript.Document.GetContent();
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
            // Console.WriteLine("Output file already exists");

            var removeFile = options.Force;
            if (!removeFile)
            {
                // Console.WriteLine($"File {options.OutputFile} already exists. Overwrite? (Y/n)");
                var response = Console.ReadLine();
                removeFile = String.IsNullOrWhiteSpace(response) || response.Equals("y", StringComparison.CurrentCultureIgnoreCase);
            }

            if (removeFile)
            {
                // Console.WriteLine("Removing file");
                File.Delete(options.OutputFile);
            }
        }

        // Console.WriteLine($"Writing to file {options.OutputFile}");
        var fileStream = File.Open(options.OutputFile, FileMode.CreateNew, FileAccess.Write, FileShare.ReadWrite);
        await fileStream.WriteAsync(Encoding.UTF8.GetBytes(content));
        fileStream.Close();
    }
}