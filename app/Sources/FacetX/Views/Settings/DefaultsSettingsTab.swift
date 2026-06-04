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

            SettingsCard(title: "Today View", systemImage: "calendar.day.timeline.left") {
                HStack(spacing: 16) {
                    Label("Timeline range", systemImage: "clock")
                        .font(SettingsUI.rowFont)
                        .foregroundStyle(.secondary)

                    Spacer()

                    // From
                    HStack(spacing: 6) {
                        Text("From")
                            .font(SettingsUI.secondaryFont)
                            .foregroundStyle(.secondary)
                        Text("\(settings.todayTimelineStartHour):00")
                            .font(SettingsUI.rowFont)
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                        Stepper("", value: $settings.todayTimelineStartHour, in: 0...22)
                            .labelsHidden()
                            .controlSize(.small)
                    }

                    // To
                    HStack(spacing: 6) {
                        Text("To")
                            .font(SettingsUI.secondaryFont)
                            .foregroundStyle(.secondary)
                        Text("\(settings.todayTimelineEndHour):00")
                            .font(SettingsUI.rowFont)
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                        Stepper("", value: $settings.todayTimelineEndHour, in: 1...23)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                }
                .padding(.vertical, 3)

                Text("Defines the visible hours on the Today timeline sidebar.")
                    .font(SettingsUI.secondaryFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        .onAppear {
            ensureDefaults()
            ensureTimelineRange()
        }
        .onChange(of: settings.changeToken) { ensureDefaults() }
        .onChange(of: settings.todayTimelineStartHour) {
            if settings.todayTimelineStartHour >= settings.todayTimelineEndHour {
                settings.todayTimelineEndHour = min(settings.todayTimelineStartHour + 1, 23)
            }
        }
        .onChange(of: settings.todayTimelineEndHour) {
            if settings.todayTimelineEndHour <= settings.todayTimelineStartHour {
                settings.todayTimelineStartHour = max(settings.todayTimelineEndHour - 1, 0)
            }
        }
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

    private func ensureTimelineRange() {
        if settings.todayTimelineStartHour >= settings.todayTimelineEndHour {
            settings.todayTimelineEndHour = min(settings.todayTimelineStartHour + 1, 23)
        }
    }
}
