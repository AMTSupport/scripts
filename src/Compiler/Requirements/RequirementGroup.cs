// Copyright (c) 2024, 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections.Immutable;

namespace Compiler.Requirements;

public sealed class RequirementGroup {
    public Dictionary<Type, HashSet<Requirement>> StoredRequirements { get; init; }

    public RequirementGroup() => this.StoredRequirements ??= [];

    public bool AddRequirement<T>(T value) where T : Requirement {
        var typeName = value is ModuleSpec ? typeof(ModuleSpec) : typeof(T);
        if (value is ModuleSpec moduleSpec) {
            var existingModuleSpec = this.StoredRequirements.Values
                .SelectMany(static requirements => requirements)
                .OfType<ModuleSpec>()
                .FirstOrDefault(existing => existing.Name == moduleSpec.Name);
            if (existingModuleSpec is not null) {
                var mergedModuleSpec = existingModuleSpec.MergeSpecs([moduleSpec]);
                this.StoredRequirements[typeName].Remove(existingModuleSpec);
                if (!this.StoredRequirements.TryGetValue(typeName, out var mergedRequirementList)) {
                    this.StoredRequirements.Add(typeName, [mergedModuleSpec]);
                } else {
                    mergedRequirementList.Add(mergedModuleSpec);
                }
                return true;
            }
        }

        if (!this.StoredRequirements.TryGetValue(typeName, out var requirementList)) {
            this.StoredRequirements.Add(typeName, [value]);
            return true;
        }

        return requirementList.Add(value);
    }

    public ImmutableList<T> GetRequirements<T>() where T : Requirement {
        var typeName = typeof(T);
        if (this.StoredRequirements.TryGetValue(typeName, out var value)) {
            return [.. value.Cast<T>()];
        }

        return [];
    }

    public bool RemoveRequirement<T>(T value) where T : Requirement {
        var typeName = typeof(T);
        if (this.StoredRequirements.TryGetValue(typeName, out var collection)) {
            return collection.Remove(value);
        }

        return false;
    }

    public ImmutableList<Requirement> GetRequirements() {
        var rawRequirements = this.StoredRequirements.Values;
        if (rawRequirements.Count == 0) return [];

        var flattenedList = rawRequirements.ToList().SelectMany(x => x);
        // bubble sort the requirements by their weight
        return [.. flattenedList.OrderBy(x => x, new RequirementWeightSorter())];
    }
}
