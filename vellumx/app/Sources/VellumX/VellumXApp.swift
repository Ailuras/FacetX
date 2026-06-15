import SwiftUI
import AppKit
import Observation

/// Bridges SwiftUI's `openWindow` action to AppKit code (the menu bar
/// controller), so "Open VellumX" can recreate the main window even after it
/// was closed. The App captures the action on appear.
@MainActor
@Observable
final class MainWindowOpener {
    static let shared = MainWindowOpener()
    @ObservationIgnored var openAction: (() -> Void)?

    /// A paper the UI should reveal/select on the next window open. `ContentView`
    /// observes this, focuses the paper, then clears it back to nil.
    var requestedPaperId: String?

    /// Open (or re-front) the main window and ask the UI to focus `paperId`.
    func open(paperId: String? = nil) {
        if let paperId { requestedPaperId = paperId }
        open()
    }

    func open() {
        // Prefer re-fronting an existing main window (a titled standard window,
        // not the Settings or popover window) to avoid spawning duplicates.
        if let window = NSApp.windows.first(where: {
            $0.canBecomeMain && $0.styleMask.contains(.titled) && $0.frame.width >= 900
        }) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        } else {
            openAction?()   // WindowGroup window was closed — recreate it
        }
    }
}

struct VellumXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = PaperStore.shared
    @State private var settings = AppSettings.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .frame(minWidth: 900, minHeight: 550)
                .unifiedAlert()
                .overlay(alignment: .bottomTrailing) {
                    ToastContainer()
                }
                .safeAreaInset(edge: .bottom) {
                    GlobalStatusBar()
                }
                .onAppear {
                    MainWindowOpener.shared.openAction = { openWindow(id: "main") }
                }
        }
        .commands { AppCommands() }

        Settings {
            SettingsRootView()
        }
    }
}

/// Hosts the AppKit-based menu bar status item (see MenuBarController for why
/// we avoid SwiftUI's MenuBarExtra with a custom image).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var automationScheduler: AutomationScheduler?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController(store: .shared, settings: .shared)
        automationScheduler = AutomationScheduler()
        automationScheduler?.start()
        // If restart.sh set the "open on right screen" flag, honour it once then clear it.
        if UserDefaults.standard.bool(forKey: "launchOnRightScreen") {
            UserDefaults.standard.removeObject(forKey: "launchOnRightScreen")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard let screen = NSScreen.screens.max(by: { $0.frame.minX < $1.frame.minX }),
                      let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.styleMask.contains(.titled) })
                else { return }
                var f = window.frame
                let sf = screen.visibleFrame
                f.origin = CGPoint(x: sf.midX - f.width / 2, y: sf.maxY - f.height - 20)
                window.setFrame(f, display: true)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        automationScheduler?.stop()
    }
}
