import SwiftUI

struct GeneralSettingsTab: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var eventKit: EventKitService
    @State private var metadata = MetadataStore.shared
    @State private var automation = AutomationPreferences.shared
    @State private var rebuildingIndex = false
    @State private var resultMessage: String? = nil

    private var activeTopics: [TrackPref] {
        metadata.topics.filter { !$0.archived }
    }

    /// Encodes the specific-startup target as "project:<uuid>" / "topic:<uuid>"
    /// so projects and literature libraries share one picker.
    private var specificSelection: Binding<String> {
        Binding(
            get: {
                settings.startupSelectionKind == "topic"
                    ? "topic:\(settings.startupTopicID)"
                    : "project:\(settings.startupProjectID)"
            },
            set: { newValue in
                if newValue.hasPrefix("topic:") {
                    settings.startupSelectionKind = "topic"
                    settings.startupTopicID = String(newValue.dropFirst("topic:".count))
                } else if newValue.hasPrefix("project:") {
                    settings.startupSelectionKind = "project"
                    settings.startupProjectID = String(newValue.dropFirst("project:".count))
                }
            }
        )
    }

    var body: some View {
        SettingsPage(title: L10n.t(.generalTitle),
                     subtitle: L10n.t(.generalSubtitle),
                     systemImage: "gearshape",
                     warning: persistenceWarning) {
            SettingsCard(title: L10n.t(.interface), systemImage: "macwindow",
                         subtitle: L10n.pick("Menu bar presence and app language.",
                                             "菜单栏显示与应用语言。")) {
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

            SettingsCard(title: L10n.t(.startup), systemImage: "play.circle",
                         subtitle: L10n.pick("Which project or library opens when the app launches.",
                                             "应用启动时打开哪个项目或文献库。")) {
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
                            Picker("", selection: specificSelection) {
                                Section(L10n.pick("Projects", "项目")) {
                                    ForEach(store.activeProjects) { project in
                                        Text(project.name).tag("project:\(project.id.uuidString)")
                                    }
                                }
                                Section(L10n.pick("Libraries", "文献库")) {
                                    ForEach(activeTopics) { topic in
                                        Text(topic.name).tag("topic:\(topic.id.uuidString)")
                                    }
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }
            }
            .onChange(of: settings.startupProjectMode) {
                guard settings.startupProjectMode == "specific" else { return }
                let hasProject = !settings.startupProjectID.isEmpty
                let hasTopic = !settings.startupTopicID.isEmpty
                if !hasProject && !hasTopic, let first = store.activeProjects.first {
                    settings.startupSelectionKind = "project"
                    settings.startupProjectID = first.id.uuidString
                }
            }

            automationCard

            SettingsCard(title: L10n.t(.storage), systemImage: "externaldrive",
                         subtitle: L10n.pick("Where FacetX keeps its data on disk.",
                                             "FacetX 在磁盘上保存数据的位置。")) {
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

            SettingsCard(title: L10n.pick("Index Reconstruction", "索引重建"), systemImage: "arrow.counterclockwise.circle",
                         subtitle: L10n.pick("Rebuild EventKit index, cleaning up legacy notes metadata.",
                                             "重建 EventKit 索引，清理历史 notes 元数据。")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.pick("This will scan all project items in EventKit, move legacy metadata to the local SQLite database, and rewrite EventKit notes to contain only stable item IDs.",
                                   "此操作将扫描 EventKit 中的所有项目条目，将历史元数据移至本地 SQLite 数据库，并重写 EventKit notes 为纯净的 stable item ID。"))
                        .font(SettingsUI.secondaryFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)

                    HStack {
                        Button {
                            runReconstructIndex()
                        } label: {
                            if rebuildingIndex {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text(L10n.pick("Reconstruct Index Now", "立即重建索引"))
                            }
                        }
                        .disabled(rebuildingIndex)

                        if let resultMessage {
                            Text(resultMessage)
                                .font(SettingsUI.smallFont)
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
    }

    private var persistenceWarning: String? {
        store.persistenceError ?? settings.persistenceError
    }

    private var automationCard: some View {
        SettingsCard(title: L10n.pick("Literature Automation", "文献自动化"),
                     systemImage: "clock.badge.checkmark",
                     subtitle: L10n.pick("Background fetch and recommendation schedules while FacetX is open.",
                                         "FacetX 运行时的后台拉取与推荐计划。")) {
            SettingsRow(title: L10n.pick("Enable Automation", "启用自动化"), systemImage: "power") {
                Toggle("", isOn: $automation.automationEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            SettingsDivider()

            HStack(spacing: 10) {
                automationPlan(title: L10n.pick("Monthly Fetch", "每月拉取"),
                               enabled: $automation.autoFetchEnabled,
                               enabledValue: automation.autoFetchEnabled,
                               systemImage: "calendar.badge.plus",
                               tint: .blue,
                               lastRun: automation.lastAutoFetchAt) {
                    HStack(spacing: 8) {
                        Picker("", selection: clamped($automation.fetchDay, to: 1...28)) {
                            ForEach(1...28, id: \.self) { day in
                                Text(L10n.pick("Day \(day)", "\(day) 日")).tag(day)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 92)
                        DatePicker("", selection: $automation.fetchTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(width: 88)
                    }
                }

                automationPlan(title: L10n.pick("Daily Recommend", "每日推荐"),
                               enabled: $automation.autoRecommendEnabled,
                               enabledValue: automation.autoRecommendEnabled,
                               systemImage: "sparkles",
                               tint: .purple,
                               lastRun: automation.lastAutoRecommendAt) {
                    HStack(spacing: 8) {
                        DatePicker("", selection: $automation.recommendTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(width: 88)
                        Spacer()
                    }
                }
            }
            .disabled(!automation.automationEnabled)
        }
    }

    private func automationPlan<Content: View>(title: String,
                                               enabled: Binding<Bool>,
                                               enabledValue: Bool,
                                               systemImage: String,
                                               tint: Color,
                                               lastRun: Date?,
                                               @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(0.12))
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(SettingsUI.smallFont)
                        .foregroundStyle(.secondary)
                    Text(enabledValue ? L10n.pick("On", "已启用") : L10n.pick("Off", "未启用"))
                        .font(.system(size: 13, weight: .semibold))
                }

                Spacer()

                Toggle("", isOn: enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            content()
                .opacity(enabledValue ? 1 : 0.45)
                .disabled(!enabledValue)

            if let lastRun {
                Label(lastRun.formatted(date: .abbreviated, time: .shortened), systemImage: "clock.arrow.circlepath")
                    .font(SettingsUI.smallFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(FacetTheme.panel.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private func runReconstructIndex() {
        rebuildingIndex = true
        resultMessage = nil
        Task {
            let prefixes = Set(store.projects.map(\.prefix))
            let count = await eventKit.reconstructNotesIndex(
                prefixes: prefixes,
                enabledReminderLists: settings.effectiveReminderListNames,
                enabledCalendars: settings.effectiveCalendarNames
            )
            await MainActor.run {
                rebuildingIndex = false
                resultMessage = L10n.pick("Done! Migrated \(count) items.", "完成！已迁移 \(count) 个条目。")
            }
        }
    }

    private func clamped(_ value: Binding<Int>, to range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
        )
    }
}
