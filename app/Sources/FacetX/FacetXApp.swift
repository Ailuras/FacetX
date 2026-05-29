import SwiftUI

@main
struct FacetXApp: App {
    @StateObject private var eventKit = EventKitService()
    @StateObject private var store = ProjectStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(eventKit)
                .environmentObject(store)
                .environmentObject(settings)
                .frame(minWidth: 760, minHeight: 480)
        }

        // Menu bar quick-capture: add a prefixed item to a project without
        // opening the main window. Shares the same stores/services.
        MenuBarExtra(isInserted: $settings.menuBarEnabled) {
            QuickCaptureView()
                .environmentObject(eventKit)
                .environmentObject(store)
                .environmentObject(settings)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)

        // Standard macOS Settings window (⌘,). App-wide container configuration
        // lives here; project management stays in the main window.
        // Fully-qualified because our own `Settings` store would otherwise
        // shadow SwiftUI's Settings scene.
        SwiftUI.Settings {
            SettingsRootView()
                .environmentObject(eventKit)
                .environmentObject(store)
                .environmentObject(settings)
        }
    }
}

private enum MenuBarIcon {
    static var image: NSImage {
        let image = NSImage(named: "FacetXMenuBarTemplate")
            ?? NSImage(systemSymbolName: "diamond", accessibilityDescription: "FacetX")
            ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}
