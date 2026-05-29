// EventKit probe — verifies authorization flow and reads the user's real
// Reminders lists and Calendars, then groups items by DocsBot's naming
// convention (project identity = title prefix "项目名：").
//
// IMPORTANT: command-line binaries often cannot obtain EventKit authorization
// because macOS ties privacy grants to a bundled .app with a stable bundle id.
// This probe reports the authorization status honestly. If access is denied at
// the CLI level, that is itself the answer: we must ship a real .app to grant.
//
// Run:  swift probe.swift
// (Calendar/Reminders usage descriptions must exist for a bundled app; at the
//  CLI we just observe what the system allows.)

import EventKit
import Foundation

let store = EKEventStore()
let group = DispatchGroup()

// Project identity: title prefix up to a fullwidth or ASCII colon.
func projectName(of title: String) -> String? {
    for sep in ["：", ":"] {
        if let r = title.range(of: sep) {
            let prefix = String(title[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !prefix.isEmpty { return prefix }
        }
    }
    return nil
}

func authStatus(_ s: EKAuthorizationStatus) -> String {
    switch s {
    case .notDetermined: return "notDetermined"
    case .restricted:    return "restricted"
    case .denied:        return "denied"
    case .fullAccess:    return "fullAccess"
    case .writeOnly:     return "writeOnly"
    case .authorized:    return "authorized"
    @unknown default:    return "unknown"
    }
}

print("=== EventKit Probe ===")
print("Reminders status:", authStatus(EKEventStore.authorizationStatus(for: .reminder)))
print("Calendar  status:", authStatus(EKEventStore.authorizationStatus(for: .event)))
print("")

// ── Request Reminders access, then dump lists + group by project ──
group.enter()
store.requestFullAccessToReminders { granted, error in
    defer { group.leave() }
    if let error = error { print("Reminders auth error:", error.localizedDescription) }
    guard granted else {
        print("Reminders: access NOT granted at CLI level.")
        print("→ Expected if run as a bare CLI binary; need a bundled .app to grant.")
        return
    }
    let lists = store.calendars(for: .reminder)
    print("Reminders lists (\(lists.count)):")
    for l in lists { print("  • \(l.title)") }

    let pred = store.predicateForReminders(in: lists)
    let inner = DispatchGroup()
    inner.enter()
    store.fetchReminders(matching: pred) { reminders in
        defer { inner.leave() }
        let items = reminders ?? []
        print("\nReminders (\(items.count)):")
        var byProject: [String: Int] = [:]
        for r in items {
            let title = r.title ?? "(untitled)"
            let proj = projectName(of: title) ?? "(no project prefix)"
            byProject[proj, default: 0] += 1
        }
        print("Grouped by project prefix:")
        for (proj, n) in byProject.sorted(by: { $0.value > $1.value }) {
            print("  [\(n)] \(proj)")
        }
    }
    inner.wait()
}

// ── Request Calendar access, then dump calendars ──
group.enter()
store.requestFullAccessToEvents { granted, error in
    defer { group.leave() }
    if let error = error { print("Calendar auth error:", error.localizedDescription) }
    guard granted else {
        print("\nCalendar: access NOT granted at CLI level.")
        return
    }
    let cals = store.calendars(for: .event)
    print("\nCalendars (\(cals.count)):")
    for c in cals { print("  • \(c.title)") }
}

group.wait()
print("\n=== done ===")
