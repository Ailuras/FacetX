import SwiftUI

struct GeneralSettingsTab: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var eventKit: EventKitService
    @State private var metadata = MetadataStore.shared
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

            indexCard
        }
    }

    private var persistenceWarning: String? {
        store.persistenceError ?? settings.persistenceError
    }

    // MARK: - Index Reconstruction

    private var indexCard: some View {
        SettingsCard(title: L10n.pick("Index Reconstruction", "重建索引"),
                     systemImage: "arrow.triangle.2.circlepath",
                     subtitle: L10n.pick(
                        "Scans all project items, migrates legacy metadata blocks to the local database, and writes a clean ID into each EventKit note.",
                        "扫描所有项目条目，将旧元数据块迁移到本地数据库，并将每条 EventKit 笔记改写为约定的 ID。"
                     )) {
            HStack {
                if rebuildingIndex {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.pick("Rebuilding…", "重建中…"))
                        .font(SettingsUI.secondaryFont)
                        .foregroundStyle(.secondary)
                } else if let msg = resultMessage {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(msg)
                        .font(SettingsUI.secondaryFont)
                        .foregroundStyle(.secondary)
                } else {
                    Button(L10n.pick("Rebuild Index", "重建索引")) {
                        runReconstructIndex()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()
            }
        }
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
}
