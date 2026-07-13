import AppKit
import FacetXCore
import SwiftUI

/// Desktop widget dashboard: today's progress ring and stats, today's agenda
/// with tappable completion, overdue alerts, this week's goals, and a one-line
/// quick capture — all on the glass panel managed by DesktopWidgetController.
struct DesktopWidgetView: View {
    @ObservedObject var controller: DesktopWidgetController
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: WidgetDataModel
    @EnvironmentObject private var focus: FocusService

    @State private var quickText = ""
    @State private var quickProjectID: Project.ID?
    @State private var quickAddError = false
    @State private var hoveredRowID: String?

    private var projectsByPrefix: [String: Project] {
        Dictionary(store.activeProjects.map { ($0.prefix, $0) }) { first, _ in first }
    }

    private var quickProject: Project? {
        store.activeProjects.first { $0.id == quickProjectID } ?? store.activeProjects.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    if focus.session != nil {
                        focusSection
                    }
                    overviewSection
                    if !model.overdueItems.isEmpty {
                        overdueSection
                    }
                    todaySection
                    if !model.currentWeekGoals.isEmpty {
                        weekGoalSection
                    }
                }
                .padding(.bottom, 2)
            }

            quickAddBar
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: DesktopWidgetController.widgetWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    // ── Header ───────────────────────────────────────────────────────────────

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                Text("FacetX")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(todayLabel)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            iconButton(controller.isFrontMode ? "pin.fill" : "pin",
                       help: L10n.pick("Toggle between desktop layer and floating",
                                       "在桌面层与悬浮置顶之间切换")) {
                controller.toggleLayer()
            }
            iconButton("arrow.up.forward.app",
                       help: L10n.pick("Open FacetX", "打开 FacetX")) {
                openMainWindow()
            }
            iconButton("xmark",
                       help: L10n.pick("Hide widget", "隐藏小组件")) {
                settings.desktopWidgetEnabled = false
            }
        }
    }

    private var todayLabel: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: L10n.language == "zh" ? "zh_CN" : "en_US")
        fmt.dateFormat = L10n.language == "zh" ? "M月d日 EEEE" : "EEE, MMM d"
        return fmt.string(from: Date())
    }

    // ── Focus ────────────────────────────────────────────────────────────────

    @ViewBuilder
    private var focusSection: some View {
        if let session = focus.session {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.pink.opacity(0.15), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: CGFloat(focus.progress))
                        .stroke(Color.pink, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: session.isPaused ? "pause.fill" : "timer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.pink)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.target.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                    Text(session.target.projectLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(session.isPaused
                         ? L10n.pick("Paused", "已暂停")
                         : FocusService.clock(seconds: focus.remainingSeconds))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.pink)
                }

                Spacer(minLength: 4)

                iconButton(session.isPaused ? "play.fill" : "pause.fill",
                           help: session.isPaused ? L10n.pick("Resume", "继续")
                                                  : L10n.pick("Pause", "暂停")) {
                    session.isPaused ? focus.resume() : focus.pause()
                }
                iconButton("stop.fill", help: L10n.pick("End focus", "结束专注")) {
                    focus.finish()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .widgetSection()
        }
    }

    // ── Overview ─────────────────────────────────────────────────────────────

    private var overviewSection: some View {
        VStack(spacing: 9) {
            HStack(spacing: 14) {
                progressRing
                    .frame(width: 76, height: 76)

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        statTile(value: model.todayOpenCount,
                                 label: L10n.pick("Open", "待办"), tint: .green)
                        statTile(value: model.todayDoneCount,
                                 label: L10n.pick("Done", "已完成"), tint: .secondary)
                    }
                    HStack(spacing: 8) {
                        statTile(value: model.todayEventCount,
                                 label: L10n.pick("Events", "事件"), tint: .blue)
                        statTile(value: model.overdueItems.count,
                                 label: L10n.pick("Overdue", "逾期"),
                                 tint: model.overdueItems.isEmpty ? .secondary : .red)
                    }
                }
            }

            if focus.todaySeconds >= 60 {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.pink)
                    Text(L10n.pick("Focused \(FocusService.format(seconds: focus.todaySeconds)) today",
                                   "今日专注 \(FocusService.format(seconds: focus.todaySeconds))"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .widgetSection()
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.09), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(model.todayProgress ?? 0))
                .stroke(
                    AngularGradient(
                        colors: [.accentColor, .accentColor.opacity(0.55), .accentColor],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: model.todayProgress)

            VStack(spacing: 0) {
                if let progress = model.todayProgress {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(L10n.pick("today", "今日"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statTile(value: Int, label: String, tint: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(value == 0 ? Color.secondary : tint)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    // ── Overdue ──────────────────────────────────────────────────────────────

    private var overdueSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(L10n.pick("Overdue", "逾期"),
                         systemImage: "exclamationmark.circle.fill",
                         tint: .red,
                         detail: "\(model.overdueItems.count)")
            ForEach(model.overdueItems.prefix(4), id: \.id) { item in
                itemRow(item, dateStyle: .overdue)
            }
            if model.overdueItems.count > 4 {
                Text(L10n.pick("+\(model.overdueItems.count - 4) more",
                               "还有 \(model.overdueItems.count - 4) 项"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 24)
            }
        }
        .padding(12)
        .widgetSection()
    }

    // ── Today ────────────────────────────────────────────────────────────────

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(L10n.pick("Today", "今日"),
                         systemImage: "sun.max.fill",
                         tint: .orange,
                         detail: model.todayItems.isEmpty ? "" : "\(model.todayItems.count)")

            if store.activeProjects.isEmpty {
                emptyHint(L10n.pick("No projects yet. Open FacetX and create one.",
                                    "暂无项目。打开 FacetX 创建一个。"))
            } else if model.todayItems.isEmpty {
                emptyHint(L10n.pick("Nothing scheduled today.", "今天没有安排，享受专注时光。"))
            } else {
                ForEach(model.todayItems, id: \.id) { item in
                    itemRow(item, dateStyle: .time)
                }
            }
        }
        .padding(12)
        .widgetSection()
    }

    // ── Week goals ───────────────────────────────────────────────────────────

    private var weekGoalSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle(L10n.pick("Week Goals", "本周目标"),
                         systemImage: "flag.fill",
                         tint: .purple,
                         detail: ISOWeek.containing(Date()).id)
            ForEach(model.currentWeekGoals, id: \.goal.id) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle()
                        .fill(ProjectAppearance.color(for: entry.project.colorName))
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.goal.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(2)
                        Text(entry.project.name)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .widgetSection()
    }

    // ── Item rows ────────────────────────────────────────────────────────────

    private enum RowDateStyle { case time, overdue }

    private func itemRow(_ item: ProjectItem, dateStyle: RowDateStyle) -> some View {
        HStack(alignment: .center, spacing: 7) {
            if item.kind == .reminder {
                Button {
                    withAnimation(FacetTheme.listSpring) {
                        model.setCompleted(!item.isCompleted, item: item)
                    }
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(item.isCompleted ? Color.secondary : item.rowTint)
                }
                .buttonStyle(.plain)
                .help(item.isCompleted ? L10n.pick("Mark as open", "标记为未完成")
                                       : L10n.pick("Mark as done", "标记为完成"))
            } else {
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(item.kind.color)
                    .frame(width: 15)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(item.content)
                    .font(.system(size: 11, weight: .medium))
                    .strikethrough(item.isCompleted, color: .secondary)
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                    .lineLimit(1)
                if let project = projectsByPrefix[item.projectPrefix] {
                    Text(project.name)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 4)

            if focus.isFocusing(item.focusTargetID) {
                Image(systemName: "timer")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.pink)
                    .help(L10n.pick("Focusing now", "正在专注"))
            } else if hoveredRowID == item.id, !item.isCompleted {
                Button {
                    let projectName = projectsByPrefix[item.projectPrefix]?.name ?? item.projectPrefix
                    focus.start(target: item.focusTarget(projectName: projectName),
                                minutes: settings.focusDurationMinutes)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.pink)
                }
                .buttonStyle(.plain)
                .help(L10n.pick("Start focus", "开始专注"))
            }

            Text(dateLabel(item, style: dateStyle))
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(dateStyle == .overdue ? Color.red : Color.secondary)
        }
        .padding(.vertical, 1)
        .onHover { hovering in
            hoveredRowID = hovering ? item.id : (hoveredRowID == item.id ? nil : hoveredRowID)
        }
    }

    private func dateLabel(_ item: ProjectItem, style: RowDateStyle) -> String {
        guard let date = item.date else { return "" }
        switch style {
        case .overdue:
            let fmt = DateFormatter()
            fmt.dateFormat = "M/d"
            return fmt.string(from: date)
        case .time:
            if item.isAllDay || !item.hasTime {
                return L10n.pick("All day", "全天")
            }
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            if let end = item.endDate {
                return "\(fmt.string(from: date))–\(fmt.string(from: end))"
            }
            return fmt.string(from: date)
        }
    }

    // ── Quick add ────────────────────────────────────────────────────────────

    private var quickAddBar: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(store.activeProjects) { project in
                    Button(project.name) { quickProjectID = project.id }
                }
            } label: {
                HStack(spacing: 3) {
                    Circle()
                        .fill(ProjectAppearance.color(for: quickProject?.colorName))
                        .frame(width: 6, height: 6)
                    Text(quickProject?.name ?? L10n.pick("Project", "项目"))
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(store.activeProjects.isEmpty)

            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 1, height: 14)

            TextField(L10n.pick("Quick add for today…", "快速添加到今天…"), text: $quickText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .onSubmit(quickAdd)

            if quickAddError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .widgetSection()
    }

    private func quickAdd() {
        guard let project = quickProject else { return }
        let content = quickText.trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return }
        quickAddError = false

        Task {
            let listName = settings.reminderSaveTarget(projectListName: project.reminderListName)
            guard !listName.isEmpty else {
                quickAddError = true
                return
            }
            let created = await ek.createReminder(
                project: project.prefix, content: content,
                listName: listName,
                dueDate: Calendar.current.startOfDay(for: Date()),
                dueIncludesTime: false,
                tags: [],
                enabledLists: settings.effectiveReminderListNames
            )
            if created != nil {
                quickText = ""
            } else {
                quickAddError = true
            }
        }
    }

    // ── Building blocks ──────────────────────────────────────────────────────

    private func sectionTitle(_ title: String, systemImage: String,
                              tint: Color, detail: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            Spacer(minLength: 0)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 1)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    private func iconButton(_ systemName: String, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.055))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let windows = NSApp.windows.filter { $0.canBecomeMain }
        if windows.isEmpty {
            NSWorkspace.shared.open(Bundle.main.bundleURL)
        } else {
            for w in windows { w.makeKeyAndOrderFront(nil) }
        }
    }
}

private struct WidgetSectionBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
                    )
            )
    }
}

private extension View {
    /// The quiet rounded card every widget section sits on (codexU-style).
    func widgetSection() -> some View {
        modifier(WidgetSectionBackground())
    }
}
