import SwiftUI

struct GeneralSettingsTab: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SettingsPage(title: "General",
                     subtitle: "Interface and local state",
                     systemImage: "gearshape",
                     warning: persistenceWarning) {
            SettingsCard(title: "Interface", systemImage: "macwindow") {
                SettingsRow(title: "Show in Menu Bar", systemImage: "menubar.rectangle") {
                    Toggle("", isOn: $settings.menuBarEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
            }

            SettingsCard(title: "Storage", systemImage: "externaldrive") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Application Support")
                        .font(SettingsUI.rowFont)
                    Text(AppSupport.directory().path)
                        .font(SettingsUI.secondaryFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var persistenceWarning: String? {
        store.persistenceError ?? settings.persistenceError
    }
}
