// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using AMT.PowerShell.Common.Commands.Event;
using AMT.PowerShell.Common.Module.Event;

namespace AMT.PowerShell.Common.Tests.Commands.Event;

[TestFixture]
[NonParallelizable]
public sealed class EventCommandTests {
    [TearDown]
    public void TearDown() => EventStore.Reset();

    // ── Register-EventSubscription ────────────────────────────────────────

    [Test]
    public void RegisterEventSubscription_ThrowsWhenEventTypeNotRegistered() {
        var r = Invoke("Register-EventSubscription", ps => {
            ps.AddParameter("EventType", typeof(object));
            ps.AddParameter("Callback", ScriptBlock.Create("{}"));
        });

        Assert.Multiple(() => {
            Assert.That(r.ThrownException, Is.Not.Null);
            Assert.That(
                r.ThrownException!.Message,
                Does.Contain("Event type System.Object has not been registered"));
        });
    }

    [Test]
    public void RegisterEventSubscription_AddsSubscriptionToEvent() {
        RegisterEvent(typeof(TestEvent));

        Invoke("Register-EventSubscription", ps => {
            ps.AddParameter("EventType", typeof(TestEvent));
            ps.AddParameter("Callback", ScriptBlock.Create("{}"));
        });

        var reg = EventStore.Get(typeof(TestEvent));
        Assert.That(reg!.Subscriptions, Has.Count.EqualTo(1));
    }

    [Test]
    public void RegisterEventSubscription_ReturnsUniqueGuids() {
        RegisterEvent(typeof(TestEvent));

        const int count = 100;
        var ids = new HashSet<Guid>();

        for (var i = 0; i < count; i++) {
            var r = Invoke("Register-EventSubscription", ps => {
                ps.AddParameter("EventType", typeof(TestEvent));
                ps.AddParameter("Callback", ScriptBlock.Create("{}"));
            });

            Assert.That(r.Output, Has.Count.EqualTo(1));
            ids.Add((Guid)r.Output[0].BaseObject);
        }

        Assert.That(ids, Has.Count.EqualTo(count));
    }

    // ── Unregister-EventSubscription ──────────────────────────────────────

    [Test]
    public void UnregisterEventSubscription_RemovesSubscription() {
        RegisterEvent(typeof(TestEvent));

        var subscribeResult = Invoke("Register-EventSubscription", ps => {
            ps.AddParameter("EventType", typeof(TestEvent));
            ps.AddParameter("Callback", ScriptBlock.Create("{}"));
        });

        var id = (Guid)subscribeResult.Output[0].BaseObject;

        Invoke("Unregister-EventSubscription", ps => {
            ps.AddParameter("EventType", typeof(TestEvent));
            ps.AddParameter("Id", id);
        });

        var reg = EventStore.Get(typeof(TestEvent));
        Assert.That(reg!.Subscriptions, Is.Empty);
    }

    [Test]
    public void UnregisterEventSubscription_DoesNotThrowForUnknownId() {
        RegisterEvent(typeof(TestEvent));

        var r = Invoke("Unregister-EventSubscription", ps => {
            ps.AddParameter("EventType", typeof(TestEvent));
            ps.AddParameter("Id", Guid.NewGuid());
        });

        Assert.That(r.ThrownException, Is.Null);
    }

    [Test]
    public void UnregisterEventSubscription_HandlesTwoSequentialUnregistrations() {
        RegisterEvent(typeof(TestEvent));

        var r1 = Invoke("Register-EventSubscription", ps => {
            ps.AddParameter("EventType", typeof(TestEvent));
            ps.AddParameter("Callback", ScriptBlock.Create("{}"));
        });
        var r2 = Invoke("Register-EventSubscription", ps => {
            ps.AddParameter("EventType", typeof(TestEvent));
            ps.AddParameter("Callback", ScriptBlock.Create("{}"));
        });

        var id1 = (Guid)r1.Output[0].BaseObject;
        var id2 = (Guid)r2.Output[0].BaseObject;

        Invoke("Unregister-EventSubscription", ps => {
            ps.AddParameter("EventType", typeof(TestEvent));
            ps.AddParameter("Id", id1);
        });
        Assert.That(EventStore.Get(typeof(TestEvent))!.Subscriptions, Has.Count.EqualTo(1));

        Invoke("Unregister-EventSubscription", ps => {
            ps.AddParameter("EventType", typeof(TestEvent));
            ps.AddParameter("Id", id2);
        });
        Assert.That(EventStore.Get(typeof(TestEvent))!.Subscriptions, Is.Empty);
    }

    [Test]
    public void RegisterEventSubscription_AllowsReregistrationAfterUnregister() {
        RegisterEvent(typeof(TestEvent));

        var r = Invoke("Register-EventSubscription", ps => {
            ps.AddParameter("EventType", typeof(TestEvent));
            ps.AddParameter("Callback", ScriptBlock.Create("{}"));
        });
        var id = (Guid)r.Output[0].BaseObject;

        Invoke("Unregister-EventSubscription", ps => {
            ps.AddParameter("EventType", typeof(TestEvent));
            ps.AddParameter("Id", id);
        });

        var r2 = Invoke("Register-EventSubscription", ps => {
            ps.AddParameter("EventType", typeof(TestEvent));
            ps.AddParameter("Callback", ScriptBlock.Create("{}"));
        });

        Assert.That(r2.ThrownException, Is.Null);
        Assert.That(r2.Output, Has.Count.EqualTo(1));
    }

    // ── Submit-Event ──────────────────────────────────────────────────────

    [Test]
    public void SubmitEvent_DispatchesEventToSubscribers() {
        RegisterEvent(typeof(TestDispatchEvent));

        var markerFile = Path.GetTempFileName();

        try {
            // Escape path for use in script literal.
            var escapedPath = markerFile.Replace("'", "''");
            var callbackScript = $"param($e) Set-Content -Path '{escapedPath}' -Value $e.Name";

            Invoke("Register-EventSubscription", ps => {
                ps.AddParameter("EventType", typeof(TestDispatchEvent));
                ps.AddParameter("Callback", ScriptBlock.Create(callbackScript));
            });

            Invoke("Submit-Event", ps => {
                ps.AddParameter("EventInstance", new TestDispatchEvent("DispatchedValue"));
            });

            var written = File.ReadAllText(markerFile).Trim();
            Assert.That(written, Is.EqualTo("DispatchedValue"));
        } finally {
            TryDeleteFile(markerFile);
        }
    }

    // ── Register-Event idempotency ──────────────────────────────────────────

    [Test]
    public void RegisterEvent_OverwritesExistingRegistrationAndDropsSubscribers() {
        RegisterEvent(typeof(TestEvent));

        Invoke("Register-EventSubscription", ps => {
            ps.AddParameter("EventType", typeof(TestEvent));
            ps.AddParameter("Callback", ScriptBlock.Create("{}"));
        });

        // Re-registering the same type must drop the old registration and its subscribers.
        RegisterEvent(typeof(TestEvent));

        var reg = EventStore.Get(typeof(TestEvent));
        Assert.That(reg!.Subscriptions, Is.Empty);
    }

    // ── Get-CustomEvent ───────────────────────────────────────────────────

    [Test]
    public void GetCustomEvent_ReturnsRegistrationForType() {
        RegisterEvent(typeof(TestEvent));

        var r = Invoke("Get-CustomEvent", ps => {
            ps.AddParameter("EventType", typeof(TestEvent));
        });

        Assert.That(r.Output, Has.Count.EqualTo(1));
        var reg = r.Output[0].BaseObject as EventRegistration;
        Assert.That(reg, Is.Not.Null);
        Assert.That(reg!.EventType, Is.EqualTo(typeof(TestEvent)));
    }

    [Test]
    public void GetCustomEvent_AllEvents_ReturnsSingleDictionaryKeyedByType() {
        RegisterEvent(typeof(TestEvent));
        RegisterEvent(typeof(TestDispatchEvent));

        var r = Invoke("Get-CustomEvent", _ => { });

        // Legacy shape: single IDictionary<Type, EventRegistration> object, not enumerated registrations.
        Assert.That(r.Output, Has.Count.EqualTo(1));
        var dict = r.Output[0].BaseObject as IDictionary<Type, EventRegistration>;
        Assert.That(dict, Is.Not.Null);
        Assert.Multiple(() => {
            Assert.That(dict!.ContainsKey(typeof(TestEvent)), Is.True);
            Assert.That(dict!.ContainsKey(typeof(TestDispatchEvent)), Is.True);
        });
    }

    // ── Priority ordering ──────────────────────────────────────────────────

    [Test]
    public void SubmitEvent_DispatchesInAscendingPriorityOrder_LowBeforeNormalBeforeHigh() {
        RegisterEvent(typeof(TestEvent));

        var logFile = Path.GetTempFileName();
        var esc = logFile.Replace("'", "''");

        try {
            // Register in reverse order to prove it is Priority that controls sequence.
            Invoke("Register-EventSubscription", ps => {
                ps.AddParameter("EventType", typeof(TestEvent));
                ps.AddParameter("Priority", Priority.High);
                ps.AddParameter("Callback", ScriptBlock.Create($"Add-Content -Path '{esc}' -Value 'H'"));
            });
            Invoke("Register-EventSubscription", ps => {
                ps.AddParameter("EventType", typeof(TestEvent));
                ps.AddParameter("Priority", Priority.Low);
                ps.AddParameter("Callback", ScriptBlock.Create($"Add-Content -Path '{esc}' -Value 'L'"));
            });
            Invoke("Register-EventSubscription", ps => {
                ps.AddParameter("EventType", typeof(TestEvent));
                ps.AddParameter("Priority", Priority.Normal);
                ps.AddParameter("Callback", ScriptBlock.Create($"Add-Content -Path '{esc}' -Value 'N'"));
            });

            Invoke("Submit-Event", ps => ps.AddParameter("EventInstance", new TestEvent("any")));

            Assert.That(File.ReadAllLines(logFile), Is.EqualTo(new[] { "L", "N", "H" }));
        } finally {
            TryDeleteFile(logFile);
        }
    }

    // ── Unregister bool return ─────────────────────────────────────────────

    [Test]
    public void UnregisterEventSubscription_ReturnsTrueWhenSubscriptionRemoved() {
        RegisterEvent(typeof(TestEvent));

        var subResult = Invoke("Register-EventSubscription", ps => {
            ps.AddParameter("EventType", typeof(TestEvent));
            ps.AddParameter("Callback", ScriptBlock.Create("{}"));
        });
        var id = (Guid)subResult.Output[0].BaseObject;

        var r = Invoke("Unregister-EventSubscription", ps => {
            ps.AddParameter("EventType", typeof(TestEvent));
            ps.AddParameter("Id", id);
        });

        Assert.That(r.Output, Has.Count.EqualTo(1));
        Assert.That(r.Output[0].BaseObject, Is.True);
    }

    [Test]
    public void UnregisterEventSubscription_ReturnsFalseForUnknownId() {
        RegisterEvent(typeof(TestEvent));

        var r = Invoke("Unregister-EventSubscription", ps => {
            ps.AddParameter("EventType", typeof(TestEvent));
            ps.AddParameter("Id", Guid.NewGuid());
        });

        Assert.That(r.Output, Has.Count.EqualTo(1));
        Assert.That(r.Output[0].BaseObject, Is.False);
    }

    [Test]
    public void UnregisterEventSubscription_ReturnsFalseWhenEventTypeNotRegistered() {
        // Do NOT register the event type.
        var r = Invoke("Unregister-EventSubscription", ps => {
            ps.AddParameter("EventType", typeof(object));
            ps.AddParameter("Id", Guid.NewGuid());
        });

        Assert.That(r.Output, Has.Count.EqualTo(1));
        Assert.That(r.Output[0].BaseObject, Is.False);
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private static void RegisterEvent(Type type) {
        Invoke("Register-Event", ps => ps.AddParameter("EventType", type));
    }

    private static InvocationResult Invoke(string cmdlet, Action<System.Management.Automation.PowerShell> configure) {
        var iss = InitialSessionState.CreateDefault2();
        iss.Commands.Add(new SessionStateCmdletEntry("Register-Event", typeof(RegisterEventCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Get-CustomEvent", typeof(GetCustomEventCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Register-EventSubscription", typeof(RegisterEventSubscriptionCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Unregister-EventSubscription", typeof(UnregisterEventSubscriptionCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Submit-Event", typeof(SubmitEventCommand), null));

        using var runspace = RunspaceFactory.CreateRunspace(iss);
        runspace.Open();

        using var ps = System.Management.Automation.PowerShell.Create();
        ps.Runspace = runspace;
        ps.AddCommand(cmdlet);
        configure(ps);

        var output = new Collection<PSObject>();
        RuntimeException? thrown = null;

        try {
            ps.Invoke(null, output);
        } catch (RuntimeException ex) {
            thrown = ex;
        }

        return new InvocationResult(output, [.. ps.Streams.Error], thrown);
    }

    private static void TryDeleteFile(string path) {
        try { if (File.Exists(path)) File.Delete(path); } catch { }
    }

    private sealed record InvocationResult(
        Collection<PSObject> Output,
        IReadOnlyList<ErrorRecord> Errors,
        RuntimeException? ThrownException);

    // ── Test domain types ─────────────────────────────────────────────────

    private sealed class TestEvent {
        public string Name { get; }
        public TestEvent(string name) => Name = name;
    }

    private sealed class TestDispatchEvent {
        public string Name { get; }
        public TestDispatchEvent(string name) => Name = name;
    }
}
