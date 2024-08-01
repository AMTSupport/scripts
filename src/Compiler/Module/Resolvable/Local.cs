using System.Management.Automation.Language;
using System.Text.RegularExpressions;
using Compiler.Module.Compiled;
using Compiler.Requirements;
using Compiler.Text;
using Compiler.Text.Updater.Built;

namespace Compiler.Module.Resolvable;

public partial class ResolvableLocalModule : Resolvable
{
    internal readonly ScriptBlockAst _ast;

    public readonly TextEditor Editor;

    public override PathedModuleSpec ModuleSpec => (PathedModuleSpec)base.ModuleSpec;

    /// <summary>
    /// Creates a new LocalModule from the moduleSpec and a path to the root to find the path.
    /// </summary>
    /// <param name="parentPath"></param>
    /// <param name="moduleSpec"></param>
    /// <exception cref="InvalidModulePathException">Thrown when the path is not a valid module path.</exception>
    public ResolvableLocalModule(
        string parentPath,
        ModuleSpec moduleSpec
    ) : this(
        moduleSpec is PathedModuleSpec pathedModuleSpec
            ? pathedModuleSpec
            : new PathedModuleSpec(Path.GetFullPath(Path.Combine(parentPath, moduleSpec.Name)))
        )
    {
        if (!Path.IsPathRooted(parentPath)) throw new InvalidModulePathException("The parent path must be an absolute path.");
        if (!Directory.Exists(parentPath)) throw new InvalidModulePathException("The parent path must be a file.");
    }

    public ResolvableLocalModule(PathedModuleSpec moduleSpec) : base(moduleSpec)
    {
        if (!File.Exists(moduleSpec.FullPath)) throw new InvalidModulePathException($"The module path must be a file, got {moduleSpec.FullPath}");
        Editor = new TextEditor(new TextDocument(File.ReadAllLines(moduleSpec.FullPath)));
        _ast = AstHelper.GetAstReportingErrors(string.Join('\n', Editor.Document.Lines), moduleSpec.FullPath, ["ModuleNotFoundDuringParse"]);

        // Remove empty lines
        Editor.AddRegexEdit(0, EntireEmptyLineRegex(), _ => { return null; });

        // Document Blocks
        Editor.AddPatternEdit(
            5,
            DocumentationStartRegex(),
            DocumentationEndRegex(),
            (lines) => { return []; });

        // Entire Line Comments
        Editor.AddRegexEdit(10, EntireLineCommentRegex(), _ => { return null; });

        // Comments at the end of a line, after some code.
        Editor.AddRegexEdit(priority: 15, EndOfLineComment(), _ => { return null; });

        // Remove #Requires statements
        Editor.AddRegexEdit(20, RequiresStatementRegex(), _ => { return null; });

        Editor.AddEdit(static () => new HereStringUpdater());

        ThreadPool.QueueUserWorkItem(_ => ResolveRequirements());
    }

    /// <summary>
    /// Returns the module match for the given requirement.
    ///
    /// Module matches for Local files are based on only the name of the module.
    /// </summary>
    /// <param name="requirement">
    /// The requirement to match against.
    /// </param>
    /// <returns>
    /// The module match for the given requirement.
    /// </returns>
    public override ModuleMatch GetModuleMatchFor(ModuleSpec requirement)
    {
        // Local files have nothing but a name.
        if (ModuleSpec.Name == requirement.Name)
        {
            return ModuleMatch.Same;
        }

        return ModuleMatch.None;
    }

    public override void ResolveRequirements()
    {
        lock (Requirements)
        {
            AstHelper.FindDeclaredModules(_ast).ToList().ForEach(module =>
            {
                if (module.Value.TryGetValue("AST", out var obj) && obj is Ast ast)
                {
                    Editor.AddExactEdit(
                        ast.Extent.StartLineNumber - 1,
                        ast.Extent.StartColumnNumber - 1,
                        ast.Extent.EndLineNumber - 1,
                        ast.Extent.EndColumnNumber - 1,
                    _ => []
                    );
                }

                module.Value.TryGetValue("Guid", out var guid);
                module.Value.TryGetValue("MinimumVersion", out var minimumVersion);
                module.Value.TryGetValue("MaximumVersion", out var maximumVersion);
                module.Value.TryGetValue("RequiredVersion", out var requiredVersion);
                var spec = new ModuleSpec(
                    module.Key,
                    (Guid?)guid,
                    (Version?)minimumVersion,
                    (Version?)maximumVersion,
                    (Version?)requiredVersion
                );

                Requirements.AddRequirement(spec);
            });

            AstHelper.FindDeclaredNamespaces(_ast).ToList().ForEach(statement =>
            {
                Editor.AddExactEdit(
                    statement.Item2.Extent.StartLineNumber - 1,
                    statement.Item2.Extent.StartColumnNumber - 1,
                    statement.Item2.Extent.EndLineNumber - 1,
                    statement.Item2.Extent.EndColumnNumber - 1,
                    _ => []
                );

                var ns = new UsingNamespace(statement.Item1);
                Requirements.AddRequirement(ns);
            });
        }
    }

    public override Compiled.Compiled IntoCompiled() => new CompiledLocalModule(
        ModuleSpec,
        CompiledDocument.FromBuilder(Editor, 0),
        Requirements
    );

    public override bool Equals(object? obj)
    {
        if (obj is null) return false;
        if (ReferenceEquals(this, obj)) return true;
        return obj is ResolvableLocalModule other &&
            ModuleSpec.CompareTo(other.ModuleSpec) == ModuleMatch.Same &&
            Editor.Document.Lines == other.Editor.Document.Lines;
    }

    public override int GetHashCode() => ModuleSpec.GetHashCode();

    #region Regex Patterns
    [GeneratedRegex(@"^(?!\n)*$")]
    public static partial Regex EntireEmptyLineRegex();

    [GeneratedRegex(@"^(?!\n)\s*<#")]
    public static partial Regex DocumentationStartRegex();

    [GeneratedRegex(@"^(?!\n)\s*#>")]
    public static partial Regex DocumentationEndRegex();

    [GeneratedRegex(@"^(?!\n)\s*#.*$")]
    public static partial Regex EntireLineCommentRegex();

    [GeneratedRegex(@"(?!\n)\s*(?<!<)#(?!>).*$")]
    public static partial Regex EndOfLineComment();

    [GeneratedRegex(@"^\s*#Requires\s+-Version\s+\d+\.\d+")]
    private static partial Regex RequiresStatementRegex();
    #endregion
}

public class InvalidModulePathException(string message) : Exception(message);