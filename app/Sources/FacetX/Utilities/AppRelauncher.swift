import AppKit

/// Relaunches FacetX in place. Used to apply settings that are only read at
/// launch (currently the UI language): a fresh instance is started, then this
/// one terminates once the replacement is up.
enum AppRelauncher {
    @MainActor
    static func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
