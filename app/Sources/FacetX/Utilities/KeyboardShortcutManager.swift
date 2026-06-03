import AppKit
import Combine
import SwiftUI

/// Action closures published by the current focused scene.
/// Each field is optional; `nil` means the action is currently unavailable.
struct FacetXActions {
    // Navigation (ContentView scope)
    var goToday: (() -> Void)?
    var goPrevProject: (() -> Void)?
    var goNextProject: (() -> Void)?

    // View mode (ProjectDetailView scope)
    var setModeAll: (() -> Void)?
    var setModeWeek: (() -> Void)?
    var setModeMonth: (() -> Void)?
    var setModeGit: (() -> Void)?

    // Window actions (ProjectDetailView scope)
    var newItem: (() -> Void)?
    var refresh: (() -> Void)?
    var toggleShowCompleted: (() -> Void)?
    var focusSearch: (() -> Void)?

    // Item actions (ProjectDetailView scope)
    var toggleCompletion: (() -> Void)?
    var openDetail: (() -> Void)?
    var closeDetail: (() -> Void)?
    var deleteItem: (() -> Void)?
}

private struct FacetXActionsKey: FocusedValueKey {
    typealias Value = FacetXActions
}

extension FocusedValues {
    var facetXActions: FacetXActions? {
        get { self[FacetXActionsKey.self] }
        set { self[FacetXActionsKey.self] = newValue }
    }
}

/// Central router for keyboard shortcuts.
///
/// Uses three layers:
/// 1. SwiftUI `Commands` (AppCommands.swift) for ⌘-modifier shortcuts.
/// 2. NSEvent local monitor for unmodified keys (Space, Return, Esc).
/// 3. NSEvent global monitor for the Quick-Capture hotkey (⌃⌥Space).
///
/// The router is a lightweight action dispatcher; it stores closures but
/// never executes business logic itself.
@MainActor
final class KeyboardActionRouter: ObservableObject {
    /// The current actions, mutated by whichever view is focused.
    @Published var actions = FacetXActions()

    /// Whether the global Quick-Capture shortcut is enabled.
    @Published var globalShortcutEnabled = false

    private var localMonitor: Any?
    private var globalMonitor: Any?

    // MARK: – Local shortcuts (Space / Return / Esc)

    func registerLocalShortcuts() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let isTextInput = KeyboardActionRouter.firstResponderIsTextInput

            switch event.keyCode {
            case 49 where !event.modifierFlags.contains(.command):
                // Space — only when not typing
                guard !isTextInput, self.actions.toggleCompletion != nil else { return event }
                self.actions.toggleCompletion?()
                return nil
            case 36 where !event.modifierFlags.contains(.command):
                // Return — only when not typing
                guard !isTextInput, self.actions.openDetail != nil else { return event }
                self.actions.openDetail?()
                return nil
            case 53:
                // Escape
                guard self.actions.closeDetail != nil else { return event }
                self.actions.closeDetail?()
                return nil
            default:
                return event
            }
        }
    }

    // MARK: – Global shortcut (⌃⌥Space)

    /// Called when the user toggles the global shortcut in Settings.
    func setGlobalShortcutEnabled(_ enabled: Bool) {
        globalShortcutEnabled = enabled
        if enabled {
            registerGlobalShortcut()
        } else {
            unregisterGlobalShortcut()
        }
    }

    private func registerGlobalShortcut() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let hasControl = event.modifierFlags.contains(.control)
            let hasOption  = event.modifierFlags.contains(.option)
            guard event.keyCode == 49, hasControl, hasOption else { return }
            Task { @MainActor in self?.actions.goToday?() }
        }
    }

    private func unregisterGlobalShortcut() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    // MARK: – Cleanup

    func unregisterAll() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        unregisterGlobalShortcut()
    }

    // MARK: – Focus helper

    static var firstResponderIsTextInput: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        let cls = String(describing: type(of: responder))
        return cls.contains("TextField") || cls.contains("TextView") || cls.contains("SearchField")
    }
}
