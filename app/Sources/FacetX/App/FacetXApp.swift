import SwiftUI
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var automationScheduler: AutomationScheduler?

    func applicationDidFinishLaunching(_ notification: Notification) {
        automationScheduler = AutomationScheduler()
        automationScheduler?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        automationScheduler?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct FacetXApp: App {
    @NSApplicationDelegateAdaptor var appDelegate: AppDelegate

    @StateObject private var eventKit = EventKitService()
    @StateObject private var store = ProjectStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var menuBarController = MenuBarController()
    @StateObject private var widgetModel = WidgetDataModel()
    @StateObject private var widgetController = DesktopWidgetController()
    @StateObject private var focus = FocusService()
    @StateObject private var keyboard = KeyboardActionRouter()
    @StateObject private var toast = ToastController()

    var body: some Scene {
        Window("FacetX", id: "main") {
            ContentView()
                .environmentObject(eventKit)
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(keyboard)
                .environmentObject(toast)
                .environmentObject(focus)
                .task {
                    widgetModel.configure(eventKit: eventKit, store: store, settings: settings)
                    widgetController.configure(eventKit: eventKit, store: store,
                                               settings: settings, model: widgetModel, focus: focus)
                    menuBarController.configure(eventKit: eventKit, store: store, settings: settings,
                                                model: widgetModel, widgetController: widgetController,
                                                focus: focus)
                }
                .onAppear {
                    keyboard.setGlobalShortcutEnabled(settings.globalShortcutEnabled)
                }
                .frame(minWidth: 760, minHeight: 480)
        }
        .commands {
            AppCommands(router: keyboard)
        }
        // Standard macOS Settings window (⌘,). App-wide container configuration
        // lives here; project management stays in the main window.
        // Fully-qualified because our own `Settings` store would otherwise
        // shadow SwiftUI's Settings scene.
        SwiftUI.Settings {
            SettingsRootView()
                .environmentObject(eventKit)
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(keyboard)
                .environmentObject(toast)
                .environmentObject(focus)
        }
    }
}
