import SwiftUI

struct DefaultsSettingsTab: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    private var enabledReminderNames: [String] {
        ek.reminderListNames(enabled: settings.effectiveReminderListNames)
    }

    private var enabledCalendarNames: [String] {
        ek.calendarNames(enabled: settings.effectiveCalendarNames)
    }

    var body: some View {
        SettingsPage(title: "Defaults",
                     subtitle: "Where new project data is saved",
                     systemImage: "tray.and.arrow.down",
                     warning: persistenceWarning) {
            SettingsCard(title: "Project Items", systemImage: "tray.and.arrow.down") {
                SettingsRow(title: "Reminders", systemImage: "checklist") {
                    Picker("", selection: $settings.defaultReminderListName) {
                        if enabledReminderNames.isEmpty { Text("None").tag("") }
                        ForEach(enabledReminderNames, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: SettingsUI.controlWidth, alignment: .trailing)
                }

                SettingsDivider()

                SettingsRow(title: "Calendar", systemImage: "calendar") {
                    Picker("", selection: $settings.defaultCalendarName) {
                        if enabledCalendarNames.isEmpty { Text("None").tag("") }
                        ForEach(enabledCalendarNames, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: SettingsUI.controlWidth, alignment: .trailing)
                }

                SettingsDivider()

                SettingsRow(title: "Event Duration", systemImage: "clock") {
                    HStack(spacing: 8) {
                        Text("\(settings.defaultEventDurationMinutes) min")
                            .font(SettingsUI.secondaryFont)
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .trailing)
                        Stepper("", value: $settings.defaultEventDurationMinutes, in: 5...1440, step: 15)
                            .labelsHidden()
                    }
                    .frame(width: SettingsUI.controlWidth, alignment: .trailing)
                }
            }

            SettingsCard(title: "Week Goals", systemImage: "target") {
                SettingsRow(title: "Calendar", systemImage: "calendar.badge.clock") {
                    Picker("", selection: $settings.weekGoalCalendarName) {
                        if enabledCalendarNames.isEmpty { Text("None").tag("") }
                        ForEach(enabledCalendarNames, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: SettingsUI.controlWidth, alignment: .trailing)
                }

                Text("Week goals are all-day calendar events shared across projects. They are kept out of normal project item lists.")
                    .font(SettingsUI.secondaryFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: ensureDefaults)
        .onChange(of: settings.changeToken) { ensureDefaults() }
    }

    private var persistenceWarning: String? {
        store.persistenceError ?? settings.persistenceError
    }

    private func ensureDefaults() {
        if settings.defaultReminderListName.isEmpty
            || !enabledReminderNames.contains(settings.defaultReminderListName) {
            settings.defaultReminderListName = enabledReminderNames.first ?? ""
        }
        if settings.defaultCalendarName.isEmpty
            || !enabledCalendarNames.contains(settings.defaultCalendarName) {
            settings.defaultCalendarName = enabledCalendarNames.first ?? ""
        }
        if settings.weekGoalCalendarName.isEmpty
            || !enabledCalendarNames.contains(settings.weekGoalCalendarName) {
            settings.weekGoalCalendarName = settings.defaultCalendarName.isEmpty
                ? (enabledCalendarNames.first ?? "")
                : settings.defaultCalendarName
        }
        if settings.defaultEventDurationMinutes < 5 {
            settings.defaultEventDurationMinutes = 5
        } else if settings.defaultEventDurationMinutes > 1440 {
            settings.defaultEventDurationMinutes = 1440
        }
    }
}
