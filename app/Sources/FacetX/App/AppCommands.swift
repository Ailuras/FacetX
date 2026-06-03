import SwiftUI

/// The single source of truth for FacetX's ⌘-modifier keyboard commands.
///
/// Shortcuts are exposed as real macOS menu-bar commands (discoverable, with
/// automatic key-equivalent annotations). The current focused view publishes
/// its available actions via `.focusedSceneValue(\.facetXActions, …)`;
/// AppCommands reads them back with `@FocusedValue`. When an action is
/// unavailable (nil) its menu item is automatically disabled.
struct AppCommands: Commands {
    @FocusedValue(\.facetXActions) private var actions

    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Today") { actions?.goToday?() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(actions?.goToday == nil)

            Divider()

            Button("Previous Project") { actions?.goPrevProject?() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(actions?.goPrevProject == nil)

            Button("Next Project") { actions?.goNextProject?() }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(actions?.goNextProject == nil)
        }

        CommandMenu("View") {
            Button("All") { actions?.setModeAll?() }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(actions?.setModeAll == nil)

            Button("Week") { actions?.setModeWeek?() }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(actions?.setModeWeek == nil)

            Button("Month") { actions?.setModeMonth?() }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(actions?.setModeMonth == nil)

            Button("Git") { actions?.setModeGit?() }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(actions?.setModeGit == nil)
        }

        CommandMenu("Item") {
            Button("New Item") { actions?.newItem?() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions?.newItem == nil)

            Button("Refresh") { actions?.refresh?() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(actions?.refresh == nil)

            Button("Show / Hide Completed") { actions?.toggleShowCompleted?() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(actions?.toggleShowCompleted == nil)

            Divider()

            Button("Delete") { actions?.deleteItem?() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(actions?.deleteItem == nil)
        }
    }
}
