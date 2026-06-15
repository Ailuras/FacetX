import SwiftUI
import AppKit

struct GeneralSettingsTab: View {
    @State private var store = PaperStore.shared
    @State private var settings = AppSettings.shared
    @Environment(\.settingsAlerts) private var alerts

    private var currentDir: URL { settings.resolvedStorageDirectory }
    private var pdfDir: URL { currentDir.appendingPathComponent("pdfs") }
    private var pdfDirExists: Bool {
        FileManager.default.fileExists(atPath: pdfDir.path)
    }

    private var fileURL: URL { settings.settingsFileURL }
    private var settingsFileExists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    var body: some View {
        Form {
            Section(L10n.t(.interface)) {
                Toggle(L10n.t(.showInMenuBar), isOn: $settings.menuBarEnabled)
                Picker(L10n.t(.language), selection: $settings.language) {
                    Text("English").tag("en")
                    Text("中文").tag("zh")
                }
                Text(L10n.t(.menuBarHint))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L10n.t(.storageLocation)) {
                LabeledContent(L10n.t(.currentLocation)) {
                    pathLabel(currentDir.path)
                }
                LabeledContent(L10n.t(.pdfLocation)) {
                    HStack(spacing: 8) {
                        pathLabel(pdfDir.path)
                        Button(L10n.t(.revealInFinder)) {
                            NSWorkspace.shared.activateFileViewerSelecting([pdfDir])
                        }
                        .controlSize(.small)
                        .disabled(!pdfDirExists)
                    }
                }
                HStack {
                    Button(L10n.t(.change)) { chooseFolder() }
                    if !settings.storageDirectory.isEmpty {
                        Button(L10n.t(.restoreDefault)) { presentStorageConfirm(dir: AppSettings.defaultStorageDirectory) }
                    }
                }
                Text(L10n.t(.storageHint))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L10n.t(.settingsFile)) {
                LabeledContent(L10n.t(.path)) {
                    pathLabel(fileURL.path)
                }
                HStack {
                    Button(L10n.t(.open)) { NSWorkspace.shared.open(fileURL) }
                        .disabled(!settingsFileExists)
                    Button(L10n.t(.revealInFinder)) {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    }
                    .disabled(!settingsFileExists)
                }
                Text(L10n.t(.settingsFileHint))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func pathLabel(_ path: String) -> some View {
        Text(path)
            .lineLimit(1).truncationMode(.middle)
            .textSelection(.enabled)
            .foregroundStyle(.secondary)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.t(.choose)
        panel.directoryURL = currentDir
        if panel.runModal() == .OK, let dir = panel.url { presentStorageConfirm(dir: dir) }
    }

    private func presentStorageConfirm(dir: URL) {
        if dir.standardizedFileURL == currentDir.standardizedFileURL { return }
        alerts?.present(AlertItem(
            title: L10n.t(.changeStorageTitle),
            message: L10n.t(.migratePrompt),
            actions: [
                .confirm(L10n.t(.migrateDB), action: { apply(dir: dir, migrate: true) }),
                .confirm(L10n.t(.switchOnly), action: { apply(dir: dir, migrate: false) }),
                .cancel(L10n.t(.cancel))
            ],
            textFieldValue: nil, textFieldLabel: nil
        ))
    }

    private func apply(dir: URL, migrate: Bool) {
        switch store.relocate(to: dir, migrate: migrate) {
        case .ok(let db):
            NotificationCenter.shared.showToast(
                "\(L10n.t(.storageUpdated)) \(db.deletingLastPathComponent().path)",
                type: .success
            )
        case .failed(let msg):
            NotificationCenter.shared.showToast(msg, type: .error)
        }
    }
}
