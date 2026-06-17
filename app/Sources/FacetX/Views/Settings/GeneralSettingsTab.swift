import SwiftUI

struct GeneralSettingsTab: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings
    @State private var metadata = MetadataStore.shared
    @State private var automation = AutomationPreferences.shared

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
            SettingsRow(title: L10n.pick("Monthly Fetch", "每月拉取"), systemImage: "calendar.badge.plus") {
                HStack(spacing: 8) {
                    Toggle("", isOn: $automation.autoFetchEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    if automation.autoFetchEnabled {
                        Picker("", selection: clamped($automation.fetchDay, to: 1...28)) {
                            ForEach(1...28, id: \.self) { day in
                                Text(L10n.pick("Day \(day)", "\(day) 日")).tag(day)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 84)
                        DatePicker("", selection: $automation.fetchTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(width: 86)
                    }
                }
                .disabled(!automation.automationEnabled)
            }
            SettingsDivider()
            SettingsRow(title: L10n.pick("Daily Recommend", "每日推荐"), systemImage: "sparkles") {
                HStack(spacing: 8) {
                    Toggle("", isOn: $automation.autoRecommendEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    if automation.autoRecommendEnabled {
                        DatePicker("", selection: $automation.recommendTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(width: 86)
                    }
                }
                .disabled(!automation.automationEnabled)
            }
            if automation.lastAutoFetchAt != nil || automation.lastAutoRecommendAt != nil {
                SettingsDivider()
                VStack(alignment: .leading, spacing: 5) {
                    if let last = automation.lastAutoFetchAt {
                        Text(L10n.pick("Last fetch: \(last.formatted(date: .abbreviated, time: .shortened))",
                                       "上次拉取：\(last.formatted(date: .abbreviated, time: .shortened))"))
                    }
                    if let last = automation.lastAutoRecommendAt {
                        Text(L10n.pick("Last recommend: \(last.formatted(date: .abbreviated, time: .shortened))",
                                       "上次推荐：\(last.formatted(date: .abbreviated, time: .shortened))"))
                    }
                }
                .font(SettingsUI.smallFont)
                .foregroundStyle(.secondary)
                .padding(.leading, 28)
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
