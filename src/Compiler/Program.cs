using System;
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
        public string OutputFile { get; set; }
    }

    public static void Main(string[] args)
    {
        Parser.Default.ParseArguments<Options>(args).WithParsed(o =>
        {
            Console.WriteLine($"Verbose: {o.Verbose}");
            Console.WriteLine($"Input file: {o.InputFile}");
            Console.WriteLine($"Output file: {o.OutputFile}");
        });
    }
}
