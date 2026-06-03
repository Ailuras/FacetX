import SwiftUI

/// The single source of truth for FacetX's ⌘-modifier keyboard commands.
///
/// Shortcuts are exposed as real macOS menu-bar commands (discoverable, with
/// automatic key-equivalent annotations). Commands publish to
/// `KeyboardActionRouter.commandPublisher`; views subscribe via `.onReceive`
/// and handle only the commands relevant to their scope.
struct AppCommands: Commands {
    let router: KeyboardActionRouter

    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Today") { router.commandPublisher.send(.today) }
                .keyboardShortcut("t", modifiers: .command)

            Divider()

            Button("Previous Project") { router.commandPublisher.send(.prevProject) }
                .keyboardShortcut(.upArrow, modifiers: .command)

            Button("Next Project") { router.commandPublisher.send(.nextProject) }
                .keyboardShortcut(.downArrow, modifiers: .command)
        }

        CommandMenu("View") {
            Button("All") { router.commandPublisher.send(.modeAll) }
                .keyboardShortcut("1", modifiers: .command)

            Button("Week") { router.commandPublisher.send(.modeWeek) }
                .keyboardShortcut("2", modifiers: .command)

            Button("Month") { router.commandPublisher.send(.modeMonth) }
                .keyboardShortcut("3", modifiers: .command)

            Button("Git") { router.commandPublisher.send(.modeGit) }
                .keyboardShortcut("4", modifiers: .command)
        }

        CommandMenu("Item") {
            Button("New Item") { router.commandPublisher.send(.newItem) }
                .keyboardShortcut("n", modifiers: .command)

            Button("Refresh") { router.commandPublisher.send(.refresh) }
                .keyboardShortcut("r", modifiers: .command)

            Button("Show / Hide Completed") { router.commandPublisher.send(.toggleShowCompleted) }
                .keyboardShortcut("h", modifiers: [.command, .shift])

            Divider()

            Button("Delete") { router.commandPublisher.send(.deleteItem) }
                .keyboardShortcut(.delete, modifiers: .command)
        }
    }
}
