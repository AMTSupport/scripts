// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Reflection;

namespace AMT.PowerShell.Common.Commands.ModuleUtils;

// Reflection wrapper over the internal System.Management.Automation.TypeAccelerators
// static class, which the PowerShellStandard reference assembly does not expose.
internal static class TypeAccelerators {
    private const string TypeAcceleratorsTypeName = "System.Management.Automation.TypeAccelerators";

    private static readonly Type? AcceleratorsType =
        typeof(PSObject).Assembly.GetType(TypeAcceleratorsTypeName);

    private static readonly PropertyInfo? GetProperty =
        FindProperty(AcceleratorsType, "Get");

    private static readonly MethodInfo? AddMethod =
        FindMethod(AcceleratorsType, "Add", typeof(string), typeof(Type));

    private static readonly MethodInfo? RemoveMethod =
        FindMethod(AcceleratorsType, "Remove", typeof(string));

    internal static Type? AcceleratorsTypeRef => AcceleratorsType;

    internal static Dictionary<string, Type> Get() {
        if (GetProperty is null) {
            throw new InvalidOperationException(
                $"Unable to resolve the internal '{TypeAcceleratorsTypeName}.Get' property.");
        }

        return (Dictionary<string, Type>)GetProperty.GetValue(null)!;
    }

    internal static void Add(string name, Type type) {
        if (AddMethod is null) {
            throw new InvalidOperationException(
                $"Unable to resolve the internal '{TypeAcceleratorsTypeName}.Add' method.");
        }

        AddMethod.Invoke(null, new object[] { name, type });
    }

    internal static bool Remove(string name) {
        if (RemoveMethod is null) {
            throw new InvalidOperationException(
                $"Unable to resolve the internal '{TypeAcceleratorsTypeName}.Remove' method.");
        }

        return (bool)RemoveMethod.Invoke(null, new object[] { name })!;
    }

    internal static bool Contains(string name) => Get().ContainsKey(name);

    private static PropertyInfo? FindProperty(Type? type, string name) {
        if (type is null) {
            return null;
        }

        return type.GetProperty(name, BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic);
    }

    private static MethodInfo? FindMethod(Type? type, string name, params Type[] parameterTypes) {
        if (type is null) {
            return null;
        }

        foreach (var method in type.GetMethods(BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)) {
            if (!string.Equals(method.Name, name, StringComparison.Ordinal)) {
                continue;
            }

            var parameters = method.GetParameters();
            if (parameters.Length != parameterTypes.Length) {
                continue;
            }

            var matches = true;
            for (var i = 0; i < parameters.Length; i++) {
                if (parameters[i].ParameterType != parameterTypes[i]) {
                    matches = false;
                    break;
                }
            }

            if (matches) {
                return method;
            }
        }

        return null;
    }
}
