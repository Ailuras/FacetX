import SwiftUI

/// The single source of truth for VellumX's keyboard commands.
///
/// Shortcuts are exposed as real macOS menu-bar commands (discoverable, with
/// automatic key-equivalent annotations) instead of being scattered across
/// view-local `.keyboardShortcut` modifiers. `ContentView` publishes the set of
/// currently-runnable actions via `focusedSceneValue(\.paperActions, …)`; each
/// command reads it back with `@FocusedValue`. When an action is unavailable
/// (no paper selected, a fetch in flight, focus on the Settings window) its
/// closure is `nil` and the matching menu item is disabled.

// MARK: - Published actions

/// Snapshot of the actions the focused window can currently perform. Optional
/// closures encode enabled/disabled state: a `nil` closure greys out its item.
struct PaperActions {
    var selectView: (SidebarItem) -> Void
    var selectPrevious: (() -> Void)?
    var selectNext: (() -> Void)?
    var setStatus: ((PaperStatus) -> Void)?
    var addTag: (() -> Void)?
    var fetch: (() -> Void)?
    var recommend: (() -> Void)?
    var copyBibtex: (() -> Void)?
    var openLink: (() -> Void)?
    var clearFilters: (() -> Void)?
    var exportBibliography: (() -> Void)?
    var surpriseMe: (() -> Void)?
    var translateAbstract: (() -> Void)?
}

private struct PaperActionsKey: FocusedValueKey {
    typealias Value = PaperActions
}

extension FocusedValues {
    var paperActions: PaperActions? {
        get { self[PaperActionsKey.self] }
        set { self[PaperActionsKey.self] = newValue }
    }
}

// MARK: - Commands

struct AppCommands: Commands {
    @FocusedValue(\.paperActions) private var actions

    var body: some Commands {
        // View menu — sidebar switches follow the on-screen order
        // (Recommended … All Papers) so ⌘N matches the visible row N.
        CommandMenu(L10n.t(.menuView)) {
            Group {
                Button(L10n.t(.cmdRecommended)) { actions?.selectView(.recommended) }
                    .keyboardShortcut("1", modifiers: .command)
                Button(L10n.t(.cmdPending))     { actions?.selectView(.pending) }
                    .keyboardShortcut("2", modifiers: .command)
                Button(L10n.t(.cmdRead))        { actions?.selectView(.read) }
                    .keyboardShortcut("3", modifiers: .command)
                Button(L10n.t(.cmdStarred))     { actions?.selectView(.starred) }
                    .keyboardShortcut("4", modifiers: .command)
                Button(L10n.t(.cmdSkipped))     { actions?.selectView(.skipped) }
                    .keyboardShortcut("5", modifiers: .command)
                Button(L10n.t(.cmdAllPapers))   { actions?.selectView(.all) }
                    .keyboardShortcut("6", modifiers: .command)
            }
            .disabled(actions == nil)

            Divider()

            Button(L10n.t(.cmdPrevPaper)) { actions?.selectPrevious?() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(actions?.selectPrevious == nil)
            Button(L10n.t(.cmdNextPaper)) { actions?.selectNext?() }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(actions?.selectNext == nil)

            Divider()

            Button(L10n.t(.cmdClearFilters)) { actions?.clearFilters?() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(actions?.clearFilters == nil)
        }

        CommandMenu(L10n.t(.menuPaper)) {
            Button(L10n.t(.cmdFetch))     { actions?.fetch?() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(actions?.fetch == nil)
            Button(L10n.t(.cmdRecommend)) { actions?.recommend?() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(actions?.recommend == nil)
            Button(L10n.t(.cmdSurprise)) { actions?.surpriseMe?() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(actions?.surpriseMe == nil)

            Divider()

            // Status of the selected paper. ⌥⌘N follows the sidebar status
            // order (Pending, Read, Starred, Skipped).
            Group {
                Button(L10n.t(.cmdMarkPending)) { actions?.setStatus?(.pending) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button(L10n.t(.cmdMarkRead))    { actions?.setStatus?(.read) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button(L10n.t(.cmdMarkStarred)) { actions?.setStatus?(.starred) }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Button(L10n.t(.cmdMarkSkip))    { actions?.setStatus?(.skip) }
                    .keyboardShortcut("4", modifiers: [.command, .option])
            }
            .disabled(actions?.setStatus == nil)

            Divider()

            Button(L10n.t(.cmdAddTag)) { actions?.addTag?() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(actions?.addTag == nil)
            Button(L10n.t(.cmdTranslateAbstract)) { actions?.translateAbstract?() }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(actions?.translateAbstract == nil)

            Divider()

            Button(L10n.t(.cmdCopyBibtex)) { actions?.copyBibtex?() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(actions?.copyBibtex == nil)
            Button(L10n.t(.cmdOpenLink)) { actions?.openLink?() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(actions?.openLink == nil)

            Divider()

            Button(L10n.t(.cmdExportBib)) { actions?.exportBibliography?() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(actions?.exportBibliography == nil)
        }
    }
}
