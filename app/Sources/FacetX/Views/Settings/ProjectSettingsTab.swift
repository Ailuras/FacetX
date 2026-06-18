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
        SettingsCard(title: L10n.pick("Project Defaults", "项目默认值"), systemImage: "tray.and.arrow.down",
                     subtitle: L10n.pick("Where new items and week goals are saved.",
                                         "新建条目与周目标的保存位置。")) {
            VStack(spacing: 0) {
                defaultPickerRow(title: L10n.pick("Task List", "任务列表"),
                                 systemImage: "checklist",
                                 selection: $settings.defaultReminderListName,
                                 values: enabledReminderNames)
                compactDivider
                defaultPickerRow(title: L10n.pick("Item Calendar", "条目日历"),
                                 systemImage: "calendar",
                                 selection: $settings.defaultCalendarName,
                                 values: enabledCalendarNames)
                compactDivider
                defaultPickerRow(title: L10n.pick("Paper List", "文献列表"),
                                 systemImage: "books.vertical",
                                 selection: $settings.defaultLiteratureListName,
                                 values: enabledReminderNames)
                if settings.defaultReminderListName == settings.defaultLiteratureListName && !settings.defaultReminderListName.isEmpty {
                    compactDivider
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                        Text(L10n.pick("Default Task List and default Paper List should not be the same.",
                                       "默认任务列表与默认文献列表不应相同。"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                }
                compactDivider
                durationPickerRow(title: L10n.pick("Event Duration", "事件时长"),
                                  systemImage: "clock",
                                  subtitle: L10n.pick("Applies to Item Calendar and Literature Calendar.",
                                                     "适用于条目日历与文献日历。"),
                                  selection: $settings.defaultEventDurationMinutes)
                compactDivider
                defaultPickerRow(title: L10n.pick("Week Goal Calendar", "周目标日历"),
                                 systemImage: "target",
                                 selection: $settings.weekGoalCalendarName,
                                 values: enabledCalendarNames)
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

    private var swipeActionsCard: some View {
        SettingsCard(title: L10n.pick("Swipe Actions", "滑动操作"), systemImage: "hand.draw",
                     subtitle: L10n.pick("Quick actions revealed by swiping a list item.",
                                         "滑动列表条目时显示的快捷操作。")) {
            VStack(spacing: 0) {
                swipeActionRow(title: L10n.pick("Swipe right", "右滑"),
                               systemImage: "arrow.right",
                               selection: $settings.leadingSwipeAction)
                compactDivider
                swipeActionRow(title: L10n.pick("Swipe left", "左滑"),
                               systemImage: "arrow.left",
                               selection: $settings.trailingSwipeAction)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(FacetTheme.panel.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                    .stroke(FacetTheme.hairline, lineWidth: 1)
            )

            settingsNote(L10n.pick("Complete applies to tasks only. Other actions are shared by All, Today and Week.",
                                   "完成仅对任务生效。其他操作在全部、今天和周视图中共用。"),
                         systemImage: "info.circle")
        }
    }

    private var todayViewCard: some View {
        SettingsCard(title: L10n.pick("Today View", "今天视图"), systemImage: "calendar.day.timeline.left",
                     subtitle: L10n.pick("Visible hour range on the Today timeline.",
                                         "今天时间线显示的小时范围。")) {
            timelinePreview

            VStack(spacing: 0) {
                SettingsRow(title: L10n.pick("Start Hour", "开始时间"), systemImage: "sunrise") {
                    hourStepper(value: $settings.todayTimelineStartHour, range: 0...22)
                }
                compactDivider
                SettingsRow(title: L10n.pick("End Hour", "结束时间"), systemImage: "sunset") {
                    hourStepper(value: $settings.todayTimelineEndHour, range: 1...23)
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

    // MARK: - Helpers

    private func defaultPickerRow(title: String, systemImage: String,
                                  selection: Binding<String>, values: [String]) -> some View {
        SettingsRow(title: title, systemImage: systemImage) {
            Menu {
                if values.isEmpty { Button(L10n.pick("None", "无")) { selection.wrappedValue = "" } }
                ForEach(values, id: \.self) { value in
                    Button(value) { selection.wrappedValue = value }
                }
            } label: {
                fixedMenuLabel(selection.wrappedValue.isEmpty ? L10n.pick("None", "无")
                                                              : selection.wrappedValue,
                               placeholder: selection.wrappedValue.isEmpty)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 1)
    }

    /// A fixed-width menu label so every dropdown in the defaults card lines up,
    /// regardless of the selected value's length.
    private func fixedMenuLabel(_ text: String, placeholder: Bool) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(placeholder ? .secondary : .primary)
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .frame(width: SettingsUI.controlWidth, height: 24)
        .background(FacetTheme.panel.opacity(0.70))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    // MARK: - Duration picker

    private static let durationPresets = [15, 30, 45, 60, 90, 120, 180, 240]

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 {
            return L10n.pick("\(minutes) min", "\(minutes) 分钟")
        }
        let h = minutes / 60
        let m = minutes % 60
        if m == 0 {
            return L10n.pick("\(h) hr", "\(h) 小时")
        }
        return L10n.pick("\(h) hr \(m) min", "\(h) 小时 \(m) 分钟")
    }

    private func durationPickerRow(title: String, systemImage: String,
                                   subtitle: String? = nil,
                                   selection: Binding<Int>) -> some View {
        SettingsRow(title: title, systemImage: systemImage, subtitle: subtitle) {
            Menu {
                ForEach(Self.durationPresets, id: \.self) { minutes in
                    Button(durationLabel(minutes)) { selection.wrappedValue = minutes }
                }
            } label: {
                fixedMenuLabel(durationLabel(selection.wrappedValue), placeholder: false)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 1)
    }

    private func swipeActionRow(title: String, systemImage: String, selection: Binding<String>) -> some View {
        SettingsRow(title: title, systemImage: systemImage) {
            let action = SwipeAction(rawValue: selection.wrappedValue) ?? .none
            HStack(spacing: 8) {
                actionBadge(action)
                swipePicker(selection: selection)
                    .frame(width: 126, alignment: .trailing)
            }
            .frame(width: SettingsUI.controlWidth, alignment: .trailing)
        }
        .padding(.vertical, 1)
    }

    private func swipePicker(selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            ForEach(SwipeAction.allCases) { action in
                Text(swipeActionTitle(action)).tag(action.rawValue)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private func actionBadge(_ action: SwipeAction) -> some View {
        HStack(spacing: 5) {
            Image(systemName: action.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 12)
            Text(swipeActionTitle(action))
                .font(SettingsUI.smallFont.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(action.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: 92, alignment: .leading)
        .background(action.tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var timelinePreview: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.blue.opacity(0.12))
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.pick("Visible Timeline", "可见时间线"))
                    .font(SettingsUI.smallFont)
                    .foregroundStyle(.secondary)
                Text("\(formattedHour(settings.todayTimelineStartHour)) - \(formattedHour(settings.todayTimelineEndHour))")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }

            Spacer()

            Text(L10n.pick("\(timelineHourCount) hours", "\(timelineHourCount) 小时"))
                .font(SettingsUI.smallFont.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(FacetTheme.quietPanel)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(FacetTheme.hairline, lineWidth: 1)
                )
        }
        .padding(10)
        .background(FacetTheme.panel.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private func hourStepper(value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 8) {
            Text(formattedHour(value.wrappedValue))
                .font(SettingsUI.rowFont)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
            Stepper("", value: value, in: range)
                .labelsHidden()
                .controlSize(.mini)
        }
        .frame(width: SettingsUI.controlWidth, alignment: .trailing)
    }

    private func settingsNote(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text)
                .font(SettingsUI.smallFont)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FacetTheme.panel.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(FacetTheme.hairline.opacity(0.72), lineWidth: 1)
        )
    }

    private var timelineHourCount: Int {
        max(settings.todayTimelineEndHour - settings.todayTimelineStartHour, 1)
    }

    private func formattedHour(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    private func swipeActionTitle(_ action: SwipeAction) -> String {
        switch action {
        case .none: return L10n.pick("None", "无")
        case .today: return L10n.pick("Today", "今天")
        case .tomorrow: return L10n.pick("Tomorrow", "明天")
        case .complete: return L10n.pick("Complete", "完成")
        case .delete: return L10n.pick("Delete", "删除")
        case .convert: return L10n.pick("Convert", "转换")
        }
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
        if settings.defaultLiteratureListName.isEmpty
            || !enabledReminderNames.contains(settings.defaultLiteratureListName) {
            settings.defaultLiteratureListName = settings.defaultReminderListName.isEmpty
                ? (enabledReminderNames.first ?? "")
                : settings.defaultReminderListName
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
