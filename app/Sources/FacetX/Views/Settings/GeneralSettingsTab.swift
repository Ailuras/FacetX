import SwiftUI

struct GeneralSettingsTab: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SettingsPage(title: L10n.t(.generalTitle),
                     subtitle: L10n.t(.generalSubtitle),
                     systemImage: "gearshape",
                     warning: persistenceWarning) {
            SettingsCard(title: L10n.t(.interface), systemImage: "macwindow") {
                SettingsRow(title: L10n.t(.showInMenuBar), systemImage: "menubar.rectangle") {
                    Toggle("", isOn: $settings.menuBarEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
                SettingsDivider()
                SettingsRow(title: L10n.t(.language), systemImage: "globe") {
                    Picker("", selection: $settings.language) {
                        Text("English").tag("en")
                        Text("中文").tag("zh")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }

            SettingsCard(title: L10n.t(.startup), systemImage: "play.circle") {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsRow(title: L10n.t(.onLaunch), systemImage: "macwindow.on.rectangle") {
                        Picker("", selection: $settings.startupProjectMode) {
                            Text(L10n.t(.startupNone)).tag("none")
                            Text(L10n.t(.startupLast)).tag("last")
                            Text(L10n.t(.startupSpecific)).tag("specific")
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    if settings.startupProjectMode == "specific" {
                        SettingsDivider()
                        SettingsRow(title: L10n.t(.startupProject), systemImage: "folder") {
                            Picker("", selection: $settings.startupProjectID) {
                                ForEach(store.activeProjects) { project in
                                    Text(project.name).tag(project.id.uuidString)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }
            }
            .onChange(of: settings.startupProjectMode) {
                if settings.startupProjectMode == "specific",
                   settings.startupProjectID.isEmpty,
                   let first = store.activeProjects.first {
                    settings.startupProjectID = first.id.uuidString
                }
            }

            SettingsCard(title: L10n.t(.storage), systemImage: "externaldrive") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t(.applicationSupport))
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
