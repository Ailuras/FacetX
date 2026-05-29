// EventKit probe v3 — enumerate SOURCES (accounts) and their containers, to
// design the container-selection settings. Output → ~/eventkit-probe-output.txt
import EventKit
import Foundation

let outPath = (NSHomeDirectory() as NSString).appendingPathComponent("eventkit-probe-output.txt")
var buffer = ""
func emit(_ s: String) { buffer += s + "\n" }
func flush() { try? buffer.write(toFile: outPath, atomically: true, encoding: .utf8) }

func sourceType(_ t: EKSourceType) -> String {
    switch t {
    case .local: return "local"; case .exchange: return "exchange"
    case .calDAV: return "calDAV/iCloud"; case .mobileMe: return "mobileMe"
    case .subscribed: return "subscribed"; case .birthdays: return "birthdays"
    @unknown default: return "unknown"
    }
}

let store = EKEventStore()
let group = DispatchGroup()
group.enter()
store.requestFullAccessToReminders { _, _ in
    store.requestFullAccessToEvents { _, _ in
        emit("=== Sources (accounts) and their containers ===\n")
        for src in store.sources {
            emit("SOURCE: \(src.title)  [\(sourceType(src.sourceType))]  id=\(src.sourceIdentifier)")
            let cals = src.calendars(for: .event).map(\.title).sorted()
            let rems = src.calendars(for: .reminder).map(\.title).sorted()
            if !cals.isEmpty { emit("  calendars: \(cals.joined(separator: ", "))") }
            if !rems.isEmpty { emit("  reminder lists: \(rems.joined(separator: ", "))") }
            emit("")
        }
        // Show that calendarIdentifier is the device-local id we must NOT persist.
        emit("--- sample calendar identifiers (device-local, do NOT persist) ---")
        for c in store.calendars(for: .event).prefix(4) {
            emit("  \(c.title): \(c.calendarIdentifier)")
        }
        emit("\n=== done ===")
        flush()
        group.leave()
    }
}
group.wait()
