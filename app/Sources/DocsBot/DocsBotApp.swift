import SwiftUI

@main
struct DocsBotApp: App {
    @StateObject private var eventKit = EventKitService()
    @StateObject private var store = ProjectStore()

    init() {
        // Headless self-test: `DOCSBOT_SELFTEST=Regulus open DocsBot.app` (or run
        // the binary directly) dumps what the app would gather for that project,
        // to ~/docsbot-selftest.txt, then exits. Used to verify the EventKit
        // contract without driving the GUI.
        if let project = ProcessInfo.processInfo.environment["DOCSBOT_SELFTEST"] {
            Task { @MainActor in
                await SelfTest.run(project: project)
                exit(0)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(eventKit)
                .environmentObject(store)
                .frame(minWidth: 760, minHeight: 480)
        }
    }
}

@MainActor
enum SelfTest {
    static func run(project: String) async {
        let out = (NSHomeDirectory() as NSString).appendingPathComponent("docsbot-selftest.txt")
        var log = "=== DocsBot self-test: project '\(project)' ===\n"
        let ek = EventKitService()
        await ek.requestAccess()
        log += "reminders auth: \(ek.remindersAuthorized), calendar auth: \(ek.calendarAuthorized)\n"
        let names = await ek.discoverProjectNames()
        log += "discovered project names (\(names.count)): \(names.joined(separator: ", "))\n"
        let items = await ek.items(forProject: project)
        log += "items for '\(project)' (\(items.count)):\n"
        for i in items {
            let kind = i.kind == .reminder ? "REM" : "EVT"
            log += "  [\(kind)] \(i.containerName) | \(i.content)"
            if i.isCompleted { log += " (done)" }
            log += "\n"
        }
        log += "=== done ===\n"
        try? log.write(toFile: out, atomically: true, encoding: .utf8)
    }
}
