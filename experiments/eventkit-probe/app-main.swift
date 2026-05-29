// Bundled-app EventKit probe (v2). Focus: verify how PROJECT TAGS can be read
// from Reminders and Calendar, since the model is "declare a project → pull
// only items carrying that project's tag". Results → ~/eventkit-probe-output.txt
// (override with PROBE_OUT).

import EventKit
import Foundation
import ObjectiveC.runtime

let outPath = ProcessInfo.processInfo.environment["PROBE_OUT"]
    ?? (NSHomeDirectory() as NSString).appendingPathComponent("eventkit-probe-output.txt")

var buffer = ""
func emit(_ s: String) { buffer += s + "\n" }
func flush() { try? buffer.write(toFile: outPath, atomically: true, encoding: .utf8) }

func authStatus(_ s: EKAuthorizationStatus) -> String {
    switch s {
    case .notDetermined: return "notDetermined"; case .restricted: return "restricted"
    case .denied: return "denied"; case .fullAccess: return "fullAccess"
    case .writeOnly: return "writeOnly"; case .authorized: return "authorized"
    @unknown default: return "unknown"
    }
}

let store = EKEventStore()
let group = DispatchGroup()

emit("=== EventKit Probe v2 — TAG support ===\n")

// ── Reminders: do they expose tags? EKReminder has no public `tags` API, but
//    macOS surfaces user tags via the KVC key "tags" on some builds. Probe both
//    the documented absence and the KVC backdoor, plus the notes field. ──
group.enter()
store.requestFullAccessToReminders { granted, error in
    defer { group.leave() }
    guard granted else { emit("Reminders: NOT granted (\(authStatus(EKEventStore.authorizationStatus(for: .reminder))))"); return }
    let lists = store.calendars(for: .reminder)
    let pred = store.predicateForReminders(in: lists)
    let inner = DispatchGroup(); inner.enter()
    store.fetchReminders(matching: pred) { reminders in
        defer { inner.leave() }
        let items = reminders ?? []
        var notesHashtagHits = 0
        // Reflect EKReminder's ObjC properties WITHOUT triggering KVC exceptions,
        // to see whether a tag-like property even exists.
        var propNames: [String] = []
        var count: UInt32 = 0
        if let props = class_copyPropertyList(EKReminder.self, &count) {
            for i in 0..<Int(count) {
                propNames.append(String(cString: property_getName(props[i])))
            }
            free(props)
        }
        let tagLike = propNames.filter { $0.lowercased().contains("tag") }
        emit("EKReminder ObjC properties (\(propNames.count)): \(propNames.sorted().joined(separator: ", "))")
        emit("  tag-like properties: \(tagLike.isEmpty ? "NONE" : tagLike.joined(separator: ", "))")
        for r in items {
            // Convention fallback: #hashtags inside notes.
            if let notes = r.notes, notes.contains("#") { notesHashtagHits += 1 }
        }
        emit("Reminders examined: \(items.count)")
        emit("  with '#' in notes : \(notesHashtagHits)")
    }
    inner.wait()
}

// ── Calendar events: no native tag. Probe what carriers exist: notes, url,
//    and whether any events already use #hashtags in notes. Sample recent. ──
group.enter()
store.requestFullAccessToEvents { granted, error in
    defer { group.leave() }
    guard granted else { emit("\nCalendar: NOT granted"); return }
    let cals = store.calendars(for: .event)
    let now = Date()
    let start = Calendar.current.date(byAdding: .month, value: -3, to: now)!
    let end = Calendar.current.date(byAdding: .month, value: 1, to: now)!
    let pred = store.predicateForEvents(withStart: start, end: end, calendars: cals)
    // Reflect EKEvent properties to confirm there is no native tag field.
    var ec: UInt32 = 0
    var eventProps: [String] = []
    if let props = class_copyPropertyList(EKEvent.self, &ec) {
        for i in 0..<Int(ec) { eventProps.append(String(cString: property_getName(props[i]))) }
        free(props)
    }
    let eventTagLike = eventProps.filter { $0.lowercased().contains("tag") }
    emit("\nEKEvent tag-like properties: \(eventTagLike.isEmpty ? "NONE" : eventTagLike.joined(separator: ", "))")

    let events = store.events(matching: pred)
    emit("Calendar events in [-3mo, +1mo]: \(events.count)")
    var withNotes = 0, withURL = 0, hashtagInNotes = 0
    for e in events {
        if let n = e.notes, !n.isEmpty { withNotes += 1; if n.contains("#") { hashtagInNotes += 1 } }
        if e.url != nil { withURL += 1 }
    }
    emit("  events with notes: \(withNotes), with url: \(withURL), '#' in notes: \(hashtagInNotes)")
    emit("  → calendar has NO native tag field; carrier must be notes/url convention.")
    emit("\n  Sample events (first 8): title | calendar | hasNotes | hasURL")
    for e in events.prefix(8) {
        emit("    - \(e.title ?? "?") | \(e.calendar.title) | \(e.notes != nil) | \(e.url != nil)")
    }
}

group.wait()
emit("\n=== done ===")
flush()
