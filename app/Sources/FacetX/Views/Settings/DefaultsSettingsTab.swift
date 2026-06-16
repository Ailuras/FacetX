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
        SettingsPage(title: L10n.pick("Defaults", "默认值"),
                     subtitle: L10n.pick("Where new project data is saved", "新建项目数据的保存位置"),
                     systemImage: "tray.and.arrow.down",
                     warning: persistenceWarning) {
            SettingsCard(title: L10n.pick("Project Items", "项目条目"), systemImage: "tray.and.arrow.down",
                         subtitle: L10n.pick("Default lists and duration for new items.",
                                             "新建条目的默认列表与时长。")) {
                SettingsRow(title: L10n.pick("Tasks", "任务"), systemImage: "checklist") {
                    Picker("", selection: $settings.defaultReminderListName) {
                        if enabledReminderNames.isEmpty { Text("None").tag("") }
                        ForEach(enabledReminderNames, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: SettingsUI.controlWidth, alignment: .trailing)
                }

                SettingsDivider()

                SettingsRow(title: L10n.pick("Calendar", "日历"), systemImage: "calendar") {
                    Picker("", selection: $settings.defaultCalendarName) {
                        if enabledCalendarNames.isEmpty { Text(L10n.pick("None", "无")).tag("") }
                        ForEach(enabledCalendarNames, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: SettingsUI.controlWidth, alignment: .trailing)
                }

                SettingsDivider()

                SettingsRow(title: L10n.pick("Event Duration", "事件时长"), systemImage: "clock") {
                    HStack(spacing: 8) {
                        Text(L10n.pick("\(settings.defaultEventDurationMinutes) min", "\(settings.defaultEventDurationMinutes) 分钟"))
                            .font(SettingsUI.secondaryFont)
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .trailing)
                        Stepper("", value: $settings.defaultEventDurationMinutes, in: 5...1440, step: 15)
                            .labelsHidden()
                            .controlSize(.mini)
                    }
                    .frame(width: SettingsUI.controlWidth, alignment: .trailing)
                }
            }

            SettingsCard(title: L10n.pick("Swipe Actions", "滑动操作"), systemImage: "hand.draw",
                         subtitle: L10n.pick("Quick actions revealed by swiping a list item.",
                                             "滑动列表条目时显示的快捷操作。")) {
                SettingsRow(title: L10n.pick("Swipe right", "右滑"), systemImage: "arrow.right") {
                    swipePicker(selection: $settings.leadingSwipeAction)
                }

                SettingsDivider()

                SettingsRow(title: L10n.pick("Swipe left", "左滑"), systemImage: "arrow.left") {
                    swipePicker(selection: $settings.trailingSwipeAction)
                }

                Text(L10n.pick("Quick actions revealed by swiping an item left or right in the All, Today and Week lists. Complete applies to tasks only.",
                               "在全部、今天和周视图列表中左右滑动条目时显示的快捷操作。完成仅对任务生效。"))
                    .font(SettingsUI.secondaryFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(title: L10n.pick("Today View", "今天视图"), systemImage: "calendar.day.timeline.left",
                         subtitle: L10n.pick("Visible hour range on the Today timeline.",
                                             "今天时间线显示的小时范围。")) {
                SettingsRow(title: L10n.pick("Timeline range", "时间线范围"), systemImage: "clock") {
                    HStack(spacing: 16) {
                        // From
                        HStack(spacing: 6) {
                            Text(L10n.pick("From", "从"))
                                .font(SettingsUI.secondaryFont)
                                .foregroundStyle(.secondary)
                            Text("\(settings.todayTimelineStartHour):00")
                                .font(SettingsUI.rowFont)
                                .monospacedDigit()
                                .frame(width: 42, alignment: .trailing)
                            Stepper("", value: $settings.todayTimelineStartHour, in: 0...22)
                                .labelsHidden()
                                .controlSize(.mini)
                        }

                        // To
                        HStack(spacing: 6) {
                            Text(L10n.pick("To", "到"))
                                .font(SettingsUI.secondaryFont)
                                .foregroundStyle(.secondary)
                            Text("\(settings.todayTimelineEndHour):00")
                                .font(SettingsUI.rowFont)
                                .monospacedDigit()
                                .frame(width: 42, alignment: .trailing)
                            Stepper("", value: $settings.todayTimelineEndHour, in: 1...23)
                                .labelsHidden()
                                .controlSize(.mini)
                        }
                    }
                    .frame(width: SettingsUI.controlWidth, alignment: .trailing)
                }

                Text(L10n.pick("Defines the visible hours on the Today timeline sidebar.",
                               "设置今天时间线侧栏显示的小时区间。"))
                    .font(SettingsUI.secondaryFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(title: L10n.pick("Week Goals", "周目标"), systemImage: "target",
                         subtitle: L10n.pick("Calendar used to store shared week goals.",
                                             "存储共享周目标所用的日历。")) {
                SettingsRow(title: L10n.pick("Calendar", "日历"), systemImage: "calendar.badge.clock") {
                    Picker("", selection: $settings.weekGoalCalendarName) {
                        if enabledCalendarNames.isEmpty { Text(L10n.pick("None", "无")).tag("") }
                        ForEach(enabledCalendarNames, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: SettingsUI.controlWidth, alignment: .trailing)
                }

                Text(L10n.pick("Week goals are all-day events shared across projects. They are kept out of normal project item lists.",
                               "周目标是跨项目共享的全天事件，不会出现在普通项目条目列表中。"))
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

    private func swipePicker(selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            ForEach(SwipeAction.allCases) { action in
                Text(action.title).tag(action.rawValue)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: SettingsUI.controlWidth, alignment: .trailing)
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
