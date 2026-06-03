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

            SettingsCard(title: "Today View", systemImage: "calendar.day.timeline.left") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Timeline range")
                            .font(SettingsUI.rowFont)
                        Spacer()
                    }

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("From")
                                .font(SettingsUI.secondaryFont)
                                .foregroundStyle(.secondary)
                            Stepper(value: $settings.todayTimelineStartHour, in: 0...22) {
                                Text("\(settings.todayTimelineStartHour):00")
                                    .font(SettingsUI.rowFont)
                                    .monospacedDigit()
                                    .frame(width: 50, alignment: .leading)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("To")
                                .font(SettingsUI.secondaryFont)
                                .foregroundStyle(.secondary)
                            Stepper(value: $settings.todayTimelineEndHour, in: 1...23) {
                                Text("\(settings.todayTimelineEndHour):00")
                                    .font(SettingsUI.rowFont)
                                    .monospacedDigit()
                                    .frame(width: 50, alignment: .leading)
                            }
                        }

                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
