import SwiftUI

/// Combined project-scoped settings: the calendar/reminder sources FacetX reads
/// plus the defaults for new project items. Both are project-related, so they
/// share one tab.
struct ProjectSettingsTab: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    @State private var containers: [EventKitService.ContainerInfo] = []

    private var allReminderNames: [String] { names(kind: .reminder) }
    private var allCalendarNames: [String] { names(kind: .calendar) }
    private var enabledReminderNames: [String] {
        ek.reminderListNames(enabled: settings.effectiveReminderListNames)
    }
    private var enabledCalendarNames: [String] {
        ek.calendarNames(enabled: settings.effectiveCalendarNames)
    }

    var body: some View {
        SettingsPage(title: L10n.pick("Project Settings", "项目设置"),
                     subtitle: L10n.pick("Sources and defaults for project items", "项目条目的数据源与默认值"),
                     systemImage: "folder",
                     warning: persistenceWarning) {
            summaryStrip

            if !duplicateContainerWarnings.isEmpty {
                duplicateContainersSection
            }

            containersSection
            projectItemsCard
            swipeActionsCard
            todayViewCard
            weekGoalsCard
        }
        .onAppear {
            reloadContainers()
            ensureTimelineRange()
        }
        .onChange(of: ek.changeToken) { reloadContainers() }
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

    // MARK: - Sources

    private var summaryStrip: some View {
        HStack(spacing: 8) {
            SummaryPill(title: L10n.pick("Reminders", "提醒事项"),
                        value: selectionSummary(enabled: enabledReminderNames.count,
                                                total: allReminderNames.count,
                                                allSelected: !settings.reminderListsDisabled && settings.enabledReminderListNames.isEmpty,
                                                allDisabled: settings.reminderListsDisabled),
                        systemImage: "checklist")
            SummaryPill(title: L10n.pick("Calendars", "日历"),
                        value: selectionSummary(enabled: enabledCalendarNames.count,
                                                total: allCalendarNames.count,
                                                allSelected: !settings.calendarsDisabled && settings.enabledCalendarNames.isEmpty,
                                                allDisabled: settings.calendarsDisabled),
                        systemImage: "calendar")

            VStack(spacing: 6) {
                sourceActionButton(title: L10n.pick("Use All", "全部启用"), systemImage: "checkmark.circle") {
                    settings.useAllContainers()
                    ensureDefaults()
                }
                sourceActionButton(title: L10n.pick("Disable All", "全部禁用"), systemImage: "xmark.circle") {
                    settings.disableAllContainers()
                    ensureDefaults()
                }
            }
            .frame(width: 118)
        }
    }

    private func sourceActionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(SettingsUI.smallFont.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private var containersSection: some View {
        SettingsCard(title: L10n.pick("Enabled Sources", "已启用的源"), systemImage: "square.stack.3d.up",
                     subtitle: L10n.pick("Toggle which lists and calendars FacetX reads.",
                                         "选择 FacetX 读取哪些列表与日历。")) {
            if containers.isEmpty {
                Text(L10n.pick("No containers found.", "未找到容器。"))
                    .font(SettingsUI.secondaryFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    containerColumn(kind: .reminder, title: L10n.pick("Reminders", "提醒事项"), icon: "checklist", color: .green)
                    containerColumn(kind: .calendar, title: L10n.pick("Calendars", "日历"), icon: "calendar", color: .blue)
                }
            }
        }
    }

    private var duplicateContainersSection: some View {
        SettingsCard(title: L10n.pick("Duplicate Names", "重名容器"), systemImage: "exclamationmark.triangle") {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.pick("FacetX stores container selections by title. Duplicate names below are enabled, disabled, and chosen as save targets together.",
                               "FacetX 按标题存储容器选择。以下重名容器会被一起启用、禁用并选作保存目标。"))
                    .font(SettingsUI.secondaryFont)
                    .foregroundStyle(.secondary)

                ForEach(Array(duplicateContainerWarnings.enumerated()), id: \.offset) { _, warning in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: warning.kind == .reminder ? "checklist" : "calendar")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(warning.kind == .reminder ? .green : .blue)
                            .frame(width: 16)
                        Text(L10n.pick("\(warning.title) appears in \(warning.sources.joined(separator: ", ")). Rename one if you need exact control.",
                                       "“\(warning.title)” 出现在 \(warning.sources.joined(separator: "、")) 中。如需精确控制请重命名其一。"))
                            .font(SettingsUI.secondaryFont)
                            .foregroundStyle(.primary.opacity(0.82))
                    }
                }
            }
        }
    }

    private func containerColumn(kind: EventKitService.ContainerInfo.Kind,
                                 title: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)

            let filtered = compactContainers.filter { $0.kind == kind }
            if filtered.isEmpty {
                Text(L10n.pick("None", "无"))
                    .font(SettingsUI.smallFont)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FacetTheme.panel.opacity(0.42))
                    .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                            .stroke(FacetTheme.hairline, lineWidth: 1)
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, container in
                        compactContainerRow(container)
                        if index < filtered.count - 1 { compactDivider }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .background(FacetTheme.panel.opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                        .stroke(FacetTheme.hairline, lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func compactContainerRow(_ container: EventKitService.ContainerInfo) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(container.kind == .reminder ? Color.green.opacity(0.12) : Color.blue.opacity(0.12))
                Image(systemName: container.kind == .reminder ? "checklist" : "calendar")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(container.kind == .reminder ? .green : .blue)
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 0) {
                Text(container.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(container.sourceTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isEnabled(container) },
                set: { _ in
                    toggle(container)
                    ensureDefaults()
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.vertical, 4)
    }

    private var compactDivider: some View {
        Divider()
            .opacity(0.36)
            .padding(.leading, 30)
    }

    private var compactContainers: [EventKitService.ContainerInfo] {
        containers.sorted {
            if $0.kind != $1.kind { return $0.kind == .reminder }
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.sourceTitle < $1.sourceTitle
        }
    }

    private var duplicateContainerWarnings: [(kind: EventKitService.ContainerInfo.Kind, title: String, sources: [String])] {
        let grouped = Dictionary(grouping: containers) { container in
            "\(container.kind.rawValue)/\(container.title)"
        }
        return grouped.compactMap { _, matches in
            guard matches.count > 1, let first = matches.first else { return nil }
            let sources = matches.map(\.sourceTitle).sorted()
            return (kind: first.kind, title: first.title, sources: sources)
        }
        .sorted {
            if $0.kind != $1.kind { return $0.kind == .reminder }
            return $0.title < $1.title
        }
    }

    // MARK: - Defaults

    private var projectItemsCard: some View {
        SettingsCard(title: L10n.pick("Project Items", "项目条目"), systemImage: "tray.and.arrow.down",
                     subtitle: L10n.pick("Default lists and duration for new items.",
                                         "新建条目的默认列表与时长。")) {
            SettingsRow(title: L10n.pick("Tasks", "任务"), systemImage: "checklist") {
                Picker("", selection: $settings.defaultReminderListName) {
                    if enabledReminderNames.isEmpty { Text(L10n.pick("None", "无")).tag("") }
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
    }

    private var swipeActionsCard: some View {
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
    }

    private var todayViewCard: some View {
        SettingsCard(title: L10n.pick("Today View", "今天视图"), systemImage: "calendar.day.timeline.left",
                     subtitle: L10n.pick("Visible hour range on the Today timeline.",
                                         "今天时间线显示的小时范围。")) {
            SettingsRow(title: L10n.pick("Timeline range", "时间线范围"), systemImage: "clock") {
                HStack(spacing: 16) {
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
    }

    private var weekGoalsCard: some View {
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

    // MARK: - Helpers

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

    private func reloadContainers() {
        containers = ek.allContainers()
        ensureDefaults()
    }

    private func names(kind: EventKitService.ContainerInfo.Kind) -> [String] {
        Array(Set(containers.filter { $0.kind == kind }.map(\.title))).sorted()
    }

    private func isEnabled(_ container: EventKitService.ContainerInfo) -> Bool {
        switch container.kind {
        case .reminder:
            return settings.isReminderListEnabled(container.title)
        case .calendar:
            return settings.isCalendarEnabled(container.title)
        }
    }

    private func toggle(_ container: EventKitService.ContainerInfo) {
        switch container.kind {
        case .reminder:
            settings.toggleReminderList(container.title, allNames: allReminderNames)
        case .calendar:
            settings.toggleCalendar(container.title, allNames: allCalendarNames)
        }
    }

    private func selectionSummary(enabled: Int, total: Int, allSelected: Bool, allDisabled: Bool) -> String {
        guard total > 0 else { return L10n.pick("None", "无") }
        if allDisabled { return "0/\(total)" }
        return allSelected ? L10n.pick("All \(total)", "全部 \(total)") : "\(enabled)/\(total)"
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
