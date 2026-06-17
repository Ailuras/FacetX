import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    static let focusSearchField = Notification.Name("com.facetx.focusSearchField")
    static let navigateToPaper = Notification.Name("com.facetx.navigateToPaper")
    static let selectPaperInTopic = Notification.Name("com.facetx.selectPaperInTopic")
    static let navigateToProjectPrefix = Notification.Name("com.facetx.navigateToProjectPrefix")
    static let selectItemInProject = Notification.Name("com.facetx.selectItemInProject")
    static let selectItemInProjectDetail = Notification.Name("com.facetx.selectItemInProjectDetail")
}

/// Commands emitted by the keyboard shortcut system.
enum KeyboardCommand {
    // Navigation
    case today, prevProject, nextProject
    // View mode
    case modeAll, modeWeek, modeMonth, modeGit
    // Window actions
    case newItem, refresh, toggleShowCompleted, focusSearch
    // Item actions
    case toggleCompletion, openDetail, closeDetail, editSelectedItemTitle, deleteItem
}

/// Central router for keyboard shortcuts.
///
/// Uses three layers:
/// 1. SwiftUI `Commands` (AppCommands.swift) for ⌘-modifier shortcuts.
///    Commands call `commandPublisher.send(...)` directly.
/// 2. NSEvent local monitor for unmodified keys (Space, Return, Esc).
/// 3. NSEvent global monitor for the Quick-Capture hotkey (⌃⌥Space).
///
/// Views subscribe to `commandPublisher` via `.onReceive` and handle only
/// the commands relevant to their scope.
@MainActor
final class KeyboardActionRouter: ObservableObject {
    let commandPublisher = PassthroughSubject<KeyboardCommand, Never>()

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
                guard !isTextInput else { return event }
                self.commandPublisher.send(.toggleCompletion)
                return nil
            case 36 where !event.modifierFlags.contains(.command):
                // Return — only when not typing
                guard !isTextInput else { return event }
                self.commandPublisher.send(.openDetail)
                return nil
            case 53:
                // Escape
                self.commandPublisher.send(.closeDetail)
                return nil
            default:
                return event
            }
        }
    }

    // MARK: – Global shortcut (⌃⌥Space)

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
            Task { @MainActor in self?.commandPublisher.send(.today) }
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
