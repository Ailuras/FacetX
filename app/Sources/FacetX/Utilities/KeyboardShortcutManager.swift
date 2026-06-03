import AppKit
import Combine
import SwiftUI

/// Central manager for keyboard shortcuts.
///
/// - Holds the global-hotkey monitor (⌃⌥Space → Quick Capture).
/// - Provides a shared `isInputFocused` flag so that list-level shortcuts
///   (Space, Return, Delete) can be suppressed while the user is typing.
@MainActor
final class KeyboardShortcutManager: ObservableObject {
    /// Set to `true` whenever *any* text field in the app becomes first
    /// responder. Views that contain text fields must bind their
    /// `FocusState` to this property via `.onChange(of:)`.
    @Published var isInputFocused = false

    /// Monitors global key events for the Quick-Capture shortcut.
    private var globalMonitor: Any?

    // MARK: – Focus helpers

    func textFieldGainedFocus() { isInputFocused = true }
    func textFieldLostFocus()   { isInputFocused = false }

    /// Checks whether the current first responder is a text-input view
    /// (NSTextField, NSTextView, NSSearchField, etc.).
    /// Use this from `.onKeyPress` handlers when you do not have direct
    /// access to SwiftUI `FocusState`.
    static var firstResponderIsTextInput: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        let cls = String(describing: type(of: responder))
        return cls.contains("TextField") || cls.contains("TextView") || cls.contains("SearchField")
    }

    // MARK: – Global shortcut

    /// Registers a global key-down monitor for ⌃⌥Space.
    /// Call once, ideally from `MenuBarController` after the menu-bar item
    /// is installed.
    func registerGlobalShortcuts(action: @escaping () -> Void) {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            // ⌃⌥Space  → keyCode 49 (spacebar)
            guard event.keyCode == 49,
                  event.modifierFlags.contains(.control),
                  event.modifierFlags.contains(.option) else { return }
            Task { @MainActor in action() }
        }
    }

    /// Clean up the global monitor. Call before discarding the manager.
    func unregister() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }
}
