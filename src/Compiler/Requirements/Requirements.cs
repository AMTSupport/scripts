using System.Collections;
using CommandLine;
using Compiler.Module;
using NLog;

namespace Compiler.Requirements;

public class RequirementGroup
{
    private readonly static Logger Logger = LogManager.GetCurrentClassLogger();
    public Hashtable StoredRequirements { get; }

    public RequirementGroup()
    {
        StoredRequirements = [];
    }

    public void AddRequirement(Requirement value)
    {
        if (!StoredRequirements.ContainsKey(value.GetType()))
        {
            StoredRequirements.Add(value.GetType(), new List<Requirement> { value });
        }
        else
        {
            StoredRequirements[value.GetType()].Cast<List<Requirement>>().Add(value);
        }
    }

    public List<T> GetRequirements<T>()
    {
        if (StoredRequirements.ContainsKey(typeof(T)))
        {
            return StoredRequirements[typeof(T)].Cast<List<Requirement>>().FindAll(requirement => requirement is T).Cast<T>().ToList();
        }

        return [];
    }

    public bool RemoveRequirement(Requirement value)
    {
        if (StoredRequirements.ContainsKey(value.GetType()))
        {
            return StoredRequirements[value.GetType()].Cast<List<Requirement>>().Remove(value);
        }

        return false;
    }

    public List<Requirement> GetRequirements()
    {
        return StoredRequirements.Values.Cast<List<Requirement>>().SelectMany(requirements => requirements).ToList();
    }

    // public void UpdateWithCompiledInplace(string rootPath, List<CompiledModule> compiledModules)
    // {
    //     foreach (var requirement in GetRequirements<ModuleSpec>())
    //     {
    //         if (requirement is not ModuleSpec moduleSpec)
    //         {
    //             continue;
    //         }

    //         var matchingModules = compiledModules.Where(module => module.ModuleSpec.RawSpec.Name == Path.GetFileNameWithoutExtension(moduleSpec.Name));
    //         if (matchingModules == null || matchingModules.Count() == 0)
    //         {
    //             Logger.Warn($"Could not find matching module for {moduleSpec.Name}");
    //             continue;
    //         }
    //         else if (matchingModules.Count() > 1)
    //         {
    //             throw new Exception($"Found multiple matching modules for {moduleSpec.Name}, this is a limitation of the current implementation, ensure unique names.");
    //         }

    //         var matchingModule = matchingModules.First();

    //         // FIXME - This may be a bad way of doing this.
    //         var newSpec = new CompiledModuleSpec(
    //             $"{matchingModule.ModuleSpec.Name}-{matchingModule.ContentHash}.psm1",
    //             moduleSpec
    //         );

    //         RemoveRequirement(moduleSpec);
    //         AddRequirement(newSpec);
    //     }
    // }

    // FIXME - Not very efficient
    public bool VerifyRequirements()
    {
        foreach (var requirement in GetRequirements<Requirement>())
        {
            foreach (var other in GetRequirements<Requirement>())
            {
                if (!requirement.IsCompatibleWith(other))
                {
                    Logger.Error($"Requirement {requirement} is incompatible with {other}");
                    return false;
                }

                Logger.Debug($"Requirement {requirement} is compatible with {other}");
            }
        }

        return true;
    }
}

public abstract record Requirement(bool SupportsMultiple)
{
    public abstract bool IsCompatibleWith(Requirement other);

    public abstract string GetInsertableLine();
}

public enum PSEdition { Desktop, Core }
