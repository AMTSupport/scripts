// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections;
using System.Management.Automation;
using Compiler.Helpers;

namespace Compiler.Test.Helpers;

[TestFixture]
public class Psd1SerializerTests {
    [Test]
    public void Serialize_BasicHashtable_ReturnsValidPsd1() {
        var table = new Hashtable {
            ["Name"] = "TestModule",
            ["Version"] = "1.0.0",
            ["GUID"] = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
        };

        var result = Psd1Serializer.Serialize(table);

        Assert.That(result, Does.StartWith("@{"));

        // Each key-value pair present, keys bareword (unquoted)
        Assert.That(result, Does.Contain("Name = 'TestModule'"));
        Assert.That(result, Does.Contain("Version = '1.0.0'"));
        Assert.That(result, Does.Contain("GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'"));

        Assert.That(result, Does.EndWith("}"));
    }

    [Test]
    public void Serialize_NestedHashtableAndArray_ReturnsValidPsd1() {
        var table = new Hashtable {
            ["RootKey"] = "root",
            ["Nested"] = new Hashtable {
                ["Inner"] = "value",
                ["Number"] = 42
            },
            ["Items"] = new object[] { "a", "b", "c" }
        };

        var result = Psd1Serializer.Serialize(table);

        // Nested hashtable opened
        Assert.That(result, Does.Contain("Nested = @{"));
        Assert.That(result, Does.Contain("Inner = 'value'"));
        Assert.That(result, Does.Contain("Number = 42"));

        // Array opened
        Assert.That(result, Does.Contain("Items = @("));
        Assert.That(result, Does.Contain("'a'"));
        Assert.That(result, Does.Contain("'b'"));
        Assert.That(result, Does.Contain("'c'"));
    }

    [Test]
    public void Serialize_StringWithSingleQuote_EscapesCorrectly() {
        var table = new Hashtable {
            ["Description"] = "It's a test"
        };

        var result = Psd1Serializer.Serialize(table);

        // Single quote inside string should be doubled
        Assert.That(result, Does.Contain("'It''s a test'"));
    }

    [Test]
    public void Serialize_MultilineString_UsesHereString() {
        var table = new Hashtable {
            ["Description"] = "Line one\nLine two"
        };

        var result = Psd1Serializer.Serialize(table);

        // Here-string delimiters
        Assert.That(result, Does.Contain("@'"));
        Assert.That(result, Does.Contain("'@"));
        // Actual line break preserved
        Assert.That(result, Does.Contain("Line one"));
        Assert.That(result, Does.Contain("Line two"));
        // No single-quote wrapping around multiline
        Assert.That(result, Does.Not.Contain("'Line one"));
    }

    [Test]
    public void Serialize_NullBoolNumeric_FormatsCorrectly() {
        var table = new Hashtable {
            ["NullVal"] = null,
            ["TrueVal"] = true,
            ["FalseVal"] = false,
            ["IntVal"] = -7,
            ["LongVal"] = long.MaxValue,
            ["DoubleVal"] = 3.14
        };

        var result = Psd1Serializer.Serialize(table);

        Assert.That(result, Does.Contain("NullVal = $Null"));
        Assert.That(result, Does.Contain("TrueVal = $True"));
        Assert.That(result, Does.Contain("FalseVal = $False"));
        Assert.That(result, Does.Contain("IntVal = -7"));
        Assert.That(result, Does.Contain("LongVal = 9223372036854775807"));
        Assert.That(result, Does.Contain("DoubleVal = 3.14"));
    }

    [Test]
    public void Serialize_EmptyHashtable_ReturnsEmptyBraces() {
        var result = Psd1Serializer.Serialize([]);
        Assert.That(result, Is.EqualTo("@{ }"));
    }

    [Test]
    public void Serialize_EmptyArray_ReturnsEmptyParens() {
        var table = new Hashtable {
            ["Empty"] = Array.Empty<object>()
        };

        var result = Psd1Serializer.Serialize(table);
        Assert.That(result, Does.Contain("Empty = @()"));
    }

    [Test]
    public void Serialize_RoundTripsThroughPowerShellParser() {
        var original = new Hashtable {
            ["ModuleVersion"] = "2.0.0",
            ["Author"] = "Test Author",
            ["RootModule"] = "Module.psm1",
            ["FunctionsToExport"] = new[] { "Get-Foo", "Set-Bar" },
            ["NestedConfig"] = new Hashtable {
                ["Enabled"] = true,
                ["RetryCount"] = 3
            }
        };

        var psd1 = Psd1Serializer.Serialize(original);

        // Parse via PowerShell's data language parser
        using var ps = PowerShell.Create();
        ps.AddScript($"$data = {psd1}; $data");

        var result = ps.Invoke();

        Assert.That(result, Has.Count.EqualTo(1));
        var psObj = result[0].BaseObject;

        Assert.That(psObj, Is.InstanceOf<Hashtable>());
        var parsed = (Hashtable)psObj;

        Assert.Multiple(() => {
            Assert.That(parsed["ModuleVersion"], Is.EqualTo("2.0.0"));
            Assert.That(parsed["Author"], Is.EqualTo("Test Author"));
            Assert.That(parsed["RootModule"], Is.EqualTo("Module.psm1"));

            // Array round-trip
            var functions = (IList?)parsed["FunctionsToExport"];
            Assert.That(functions, Is.Not.Null);
            Assert.That(functions, Has.Count.EqualTo(2));
            Assert.That(functions?[0], Is.EqualTo("Get-Foo"));
            Assert.That(functions?[1], Is.EqualTo("Set-Bar"));

            // Nested hashtable
            var nested = (Hashtable?)parsed["NestedConfig"];
            Assert.That(nested, Is.Not.Null);
            Assert.That(nested!["Enabled"], Is.True);
            Assert.That(nested["RetryCount"], Is.EqualTo(3));
        });
    }
}
