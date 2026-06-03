import SwiftUI
import AppKit

@main
struct FacetXApp: App {
    @StateObject private var eventKit = EventKitService()
    @StateObject private var store = ProjectStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var menuBarController = MenuBarController()

    var body: some Scene {
        Window("FacetX", id: "main") {
            ContentView()
                .environmentObject(eventKit)
                .environmentObject(store)
                .environmentObject(settings)
                .background {
                    MenuBarInstaller(controller: menuBarController)
                        .environmentObject(eventKit)
                        .environmentObject(store)
                        .environmentObject(settings)
                }
                .background {
                    WindowPositionRestorer()
                }
                .frame(minWidth: 760, minHeight: 480)
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
        }
    }
}

struct WindowPositionRestorer: View {
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                guard ProcessInfo.processInfo.environment["FACETX_RESTART"] == "1" else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    moveToRightScreen()
                }
            }
    }

    private func moveToRightScreen() {
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
        let screens = NSScreen.screens
        guard screens.count > 1 else { return }

        // 找最右侧的屏幕（frame 原点 x 最大）
        let rightScreen = screens.max(by: { $0.frame.minX < $1.frame.minX }) ?? screens[0]
        let screenFrame = rightScreen.visibleFrame
        let windowFrame = window.frame

        // 将窗口放到右侧屏幕右下
        let margin: CGFloat = 20
        let newX = screenFrame.maxX - windowFrame.width - margin
        let newY = screenFrame.minY + margin
        window.setFrameOrigin(NSPoint(x: newX, y: newY))
    }
}
