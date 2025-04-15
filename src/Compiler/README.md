# Compiler

This is a C# project ([Compiler.csproj](Compiler.csproj)) that compiles PowerShell scripts. The entry point is in [Program.cs](Program.cs).

The compiler takes your PowerShell scripts, analyzes them, resolves dependencies, optimizes the content, reports any issues,
and then outputs a compiled version of your script that is self-contained and ready to run.

For a more detailed explanation of how the compilation process works, see [How the Compilation Process Works](#how-the-compilation-process-works).

______________________________________________________________________

## Building

Currently this can only be built as a Windows executable due to Windows Forms and some other dependencies that are not supported on Linux/Darwin.

To build the project, run the following commands:

```sh
dotnet restore ./src/Compiler/Compiler.csproj
dotnet publish ./src/Compiler/Compiler.csproj --sc -c Release -r win-x64
```

______________________________________________________________________

## Usage

After building, run the generated Compiler.exe:

```sh
Compiler.exe -i <input> [o <outputDir>] [-f] [-v] [-q]
```

- -i, --input  : File or directory to compile
- -o, --output : Optional output directory
- -f, --force  : Force overwrite existing files
- -v, --verbosity : Logging level, can be used 3 times for tracing
- -q, --quiet : Logging level
- -h, --help : Display help information

See [Program.Options](Program.cs) for more details.

______________________________________________________________________

## How the Compilation Process Works

When you run the compiler on one or more PowerShell scripts `*.ps1` files, it performs several major steps:

1. **File Gathering & Filtering**
  The compiler begins by collecting all the scripts that should be compiled:
    - If you supply a single file as the input path (-i), it compiles just that file.
    - If the input path is a directory, the compiler recursively collects all scripts `*.ps1` under that folder.
    - Scripts that begin with the line `#!ignore` are excluded.
    - See example at [Generate.ps1](../automation/registry/Generate.ps1#L1).

2. **Parsing & Building Internal AST**
    - Each script is parsed into a PowerShell Abstract Syntax Tree (AST) (via System.Management.Automation.Language APIs).
    This helps the compiler analyze the script content (such as which functions are declared or which modules are referenced).

3. **Resolving Requirements**
    - The compiler figures out which modules or other scripts a given script depends on.

      If your script references another script or requires certain functions, the compiler determines those references and ensures each dependency is also compiled (if needed).
      - Currently modules are only discovered via the use of `Using Module` statements.
    - Any PowerShell `#Requires` statements are resolved and propagated up to the final script (e.g., RunAsAdministrator).

4. **AST Transformations & Editing**
    - Once the compiler has the AST and knows all requirements, it applies a number of transformations to the script content including but not limited to:
      - Replacing any module references with the internal hash reference.
      - Adding any required headers or metadata to the script.
      - Minimizing the output size by removing unnecessary whitespace or comments.
    - This step also includes any necessary fixes or adjustments to the script content, such as:
      - Replacing relative paths with absolute paths.
      - Fixing references to modules that are not in the same script.
      - Adding any required headers or metadata to the script.

5. **Analysis**
    - The compiler performs a final analysis of the script to try and report any potential issues
      - You can see a full list of the rules under [Rules](Analyser/Rules).
    - Some rules will be errors that block the compilation process, while others will be warnings that are reported at the end of the compilation process.

6. **Building the Final Output**
    - After making its internal transformations, the compiler converts the updated script and any required modules into a self-contained output. For example:
      - Local modules are included as a string which is written to a temporary file and loaded at runtime.
      - Remote modules are downloaded and included as a raw byte array of the zip file which is extracted at runtime.
      - The final script is written out with all dependencies included.

7. **Writing Files or Outputting to Console**
    - Finally, the compiler writes out the compiled script:
      - By default, it writes to the given output directory (-o).
      - If no output directory is given, it writes to standard output (so you can pipe the result to another command).
      - If a file of the same name already exists, the compiler can ask to overwrite it (or you can force overwriting with the -f flag).

8. **Error Logging & Debugging**
    - Any errors—like missing modules, parse failures, or references that can’t be resolved—are collected and printed at the end.

    If you enable debugging/verbosity options (e.g., -v), more information about each step is printed, including transformations to your scripts.
