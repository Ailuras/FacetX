import FacetXCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var keyboard: KeyboardActionRouter
    @EnvironmentObject private var toast: ToastController

    enum SidebarItem: Hashable { case project(Project.ID); case topic(UUID) }

    @State private var selection: SidebarItem? = nil
    @State private var tagFilter = TagFilter()
    @State private var showTodayPanel = false
    @State private var discovered: [String] = []
    @State private var draftProject: ProjectDraft?
    @State private var editingProject: Project?
    @State private var projectToDelete: Project?
    @State private var litStore = PaperStore.shared
    @State private var litMeta = MetadataStore.shared
    @State private var showTopicEditor = false
    @State private var editingTopic: TrackPref?
    @State private var topicToDelete: TrackPref?

    var body: some View {
        ZStack {
            NavigationSplitView {
                VStack(spacing: 0) {
                    if let persistenceWarning {
                        persistenceWarningView(persistenceWarning)
                    }
                    List(selection: $selection) {
                        Section(L10n.t(.sidebarProjects)) {
                            ForEach(store.activeProjects) { project in
                                ProjectSidebarRow(project: project)
                                    .tag(SidebarItem.project(project.id))
                                    .contextMenu {
                                        Button(L10n.t(.editProject)) {
                                            selection = .project(project.id)
                                            editingProject = project
                                        }
                                        Divider()
                                        Button(L10n.t(.archive)) {
                                            store.archive(project)
                                            toast.show(L10n.t(.projectArchived), type: .info)
                                        }
                                        Button(L10n.t(.delete), role: .destructive) {
                                            projectToDelete = project
                                        }
                                    }
                            }
                            .onMove { indices, newOffset in
                                store.reorderProjects(from: indices, to: newOffset)
                            }
                        }
                        if !litMeta.topics.filter({ !$0.archived }).isEmpty {
                            Section(L10n.pick("Literature", "文献")) {
                                ForEach(litMeta.topics.filter { !$0.archived }) { topic in
                                    LiteratureSidebarRow(topic: topic, paperCount: litStore.papers.filter { p in
                                        p.track.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(topic.name)
                                    }.count)
                                        .tag(SidebarItem.topic(topic.id))
                                        .contextMenu {
                                            Button(L10n.pick("Edit Library", "编辑文献库")) {
                                                editingTopic = topic
                                            }
                                            Button(L10n.t(.archive)) {
                                                litMeta.setTopicArchived(id: topic.id, true)
                                                if case .topic(let id) = selection, id == topic.id {
                                                    selection = nil
                                                }
                                                toast.show(L10n.pick("Library archived", "文献库已归档"), type: .info)
                                            }
                                            Divider()
                                            Button(L10n.t(.delete), role: .destructive) {
                                                topicToDelete = topic
                                            }
                                        }
                                }
                            }
                        }
                        if !sortedDiscoveredTags.isEmpty {
                            Section(L10n.t(.sidebarTags)) {
                                tagCloud
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 8, trailing: 10))
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    Divider()
                    HStack(spacing: 8) {
                        sidebarCreateButton(
                            title: L10n.t(.newProject),
                            systemImage: "plus.circle",
                            alignment: .leading
                        ) { startNewProject() }

                        Spacer(minLength: 8)

                        sidebarCreateButton(
                            title: L10n.pick("New Library", "新建文献库"),
                            systemImage: "books.vertical",
                            alignment: .trailing
                        ) { showTopicEditor = true }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .navigationTitle("FacetX")
            } detail: {
                HStack(spacing: 0) {
                    Group {
                        switch selection {
                        case nil:
                            ContentUnavailableView(
                                L10n.t(.selectProject),
                                systemImage: "folder",
                                description: Text(L10n.t(.selectProjectHint))
                            )
                        case .project(let id):
                            if let project = store.activeProjects.first(where: { $0.id == id }) {
                                ProjectDetailView(project: project, showTodayPanel: $showTodayPanel, tagFilter: $tagFilter)
                            } else {
                                ContentUnavailableView(L10n.t(.projectNotFound), systemImage: "folder")
                            }
                        case .topic(let id):
                            if let topic = litMeta.topics.first(where: { $0.id == id }) {
                                TopicDetailView(topic: topic, tagFilter: $tagFilter)
                            } else {
                                ContentUnavailableView(L10n.pick("Topic not found", "未找到主题"), systemImage: "tag")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showTodayPanel {
                        TodayTimelinePanel(isPresented: $showTodayPanel)
                            .transition(FacetSidebarStyle.transition)
                    }
                }
                .animation(FacetTheme.detailSpring, value: showTodayPanel)
            }
            .navigationSplitViewStyle(.balanced)
            .onReceive(keyboard.commandPublisher) { cmd in
                switch cmd {
                case .today:
                    withAnimation(FacetTheme.detailSpring) { showTodayPanel.toggle() }
                case .prevProject:    navigateProject(by: -1)
                case .nextProject:    navigateProject(by: 1)
                default:              break
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToPaper)) { notification in
                guard let paperID = notification.userInfo?["paperID"] as? String else { return }
                guard let paper = litStore.papers.first(where: { $0.id == paperID }) else { return }
                let paperTracks = paper.track.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                guard let matchedTopic = litMeta.topics.first(where: { topic in
                    !topic.archived && paperTracks.contains(topic.name)
                }) else { return }
                selection = .topic(matchedTopic.id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(name: .selectPaperInTopic, object: nil, userInfo: ["paperID": paperID])
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToProjectPrefix)) { notification in
                guard let prefix = notification.userInfo?["prefix"] as? String else { return }
                if let project = store.activeProjects.first(where: { $0.prefix == prefix }) {
                    selection = .project(project.id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectItemInProject)) { notification in
                guard let prefix = notification.userInfo?["projectPrefix"] as? String,
                      let itemID = notification.userInfo?["itemID"] as? String else { return }
                if let project = store.activeProjects.first(where: { $0.prefix == prefix }) {
                    selection = .project(project.id)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        NotificationCenter.default.post(name: .selectItemInProjectDetail, object: nil, userInfo: ["itemID": itemID])
                    }
                }
            }
            .task {
                applyStartupSelection()
                keyboard.registerLocalShortcuts()
                if !ek.remindersAuthorized && !ek.calendarAuthorized {
                    await ek.requestAccess()
                    // Show banner if access was denied
                    if !ek.remindersAuthorized && !ek.calendarAuthorized {
                        toast.showBanner(
                            L10n.t(.accessRequired),
                            type: .warning,
                            action: BannerAction(title: L10n.t(.openSettings)) {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                            }
                        )
                    }
                }
                await reloadDiscoveredProjects()
            }
            .onChange(of: settings.changeToken) { Task { await reloadDiscoveredProjects() } }
            .onChange(of: selection) {
                switch selection {
                case .project(let id):
                    settings.lastOpenedKind = "project"
                    settings.lastOpenedProjectID = id.uuidString
                case .topic(let id):
                    settings.lastOpenedKind = "topic"
                    settings.lastOpenedTopicID = id.uuidString
                case .none:
                    break
                }
            }
            .alert(L10n.t(.deleteProjectTitle), isPresented: .init(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            )) {
                Button(L10n.t(.cancel), role: .cancel) { projectToDelete = nil }
                Button(L10n.t(.delete), role: .destructive) {
                    if let project = projectToDelete {
                        store.delete(project)
                        toast.show(L10n.t(.projectDeleted), type: .success)
                    }
                    projectToDelete = nil
                }
            } message: {
                Text("“\(projectToDelete?.name ?? "")” \(L10n.t(.deleteProjectMessage))")
            }
            .sheet(item: $draftProject) { draft in
                NewProjectView(draft: draft) { name, prefix, tagline, reminderList, calendar, goalCalendar, colorName, iconName, githubRepo in
                    let id = store.createProject(name: name, prefix: prefix, tagline: tagline,
                                                  reminderListName: reminderList, calendarName: calendar,
                                                  weekGoalCalendarName: goalCalendar,
                                                  colorName: colorName,
                                                  iconName: iconName,
                                                  githubRepo: githubRepo)
                    selection = .project(id)
                    draftProject = nil
                } onCancel: {
                    draftProject = nil
                }
            }
            .sheet(item: $editingProject) { project in
                EditProjectView(project: project) { editingProject = nil }
            }
            .sheet(isPresented: $showTopicEditor) {
                TopicEditorSheet(
                    onSave: { topic in
                        litMeta.addTopic(topic)
                        selection = .topic(topic.id)
                        showTopicEditor = false
                    },
                    onCancel: { showTopicEditor = false }
                )
            }
            .sheet(item: $editingTopic) { topic in
                TopicEditorSheet(topic: topic,
                    onSave: { updated in
                        litMeta.updateTopic(updated)
                        editingTopic = nil
                    },
                    onCancel: { editingTopic = nil }
                )
            }
            .alert(L10n.pick("Delete “\(topicToDelete?.name ?? "")”?", "删除“\(topicToDelete?.name ?? "")”？"), isPresented: .init(
                get: { topicToDelete != nil },
                set: { if !$0 { topicToDelete = nil } }
            )) {
                Button(L10n.t(.cancel), role: .cancel) { topicToDelete = nil }
                Button(L10n.t(.delete), role: .destructive) {
                    if let topic = topicToDelete {
                        litStore.purgeTopicPapers(topic.name)
                        litMeta.deleteTopic(id: topic.id)
                        if case .topic(let id) = selection, id == topic.id {
                            selection = nil
                        }
                        toast.show(L10n.pick("Library deleted", "文献库已删除"), type: .success)
                    }
                    topicToDelete = nil
                }
            } message: {
                Text(L10n.pick("Papers only in this library will also be deleted.",
                               "仅属于该文献库的文献也会被一并删除。"))
            }

            // Banner overlay (top)
            if let banner = toast.banner {
                VStack {
                    BannerView(banner: banner) {
                        toast.dismissBanner()
                    }
                    Spacer()
                }
                .allowsHitTesting(true)
            }

            // Toast overlay (bottom-trailing)
            ToastStack()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .allowsHitTesting(true)
        }
    }

    /// On launch, open the last opened or a specific project / literature library
    /// per the user's startup preference, or nothing.
    private func applyStartupSelection() {
        guard selection == nil else { return }
        let kind: String
        let rawID: String
        switch settings.startupProjectMode {
        case "last":
            kind = settings.lastOpenedKind
            rawID = kind == "topic" ? settings.lastOpenedTopicID : settings.lastOpenedProjectID
        case "specific":
            kind = settings.startupSelectionKind
            rawID = kind == "topic" ? settings.startupTopicID : settings.startupProjectID
        default:
            return
        }
        guard let id = UUID(uuidString: rawID) else { return }
        if kind == "topic" {
            if litMeta.topics.contains(where: { $0.id == id && !$0.archived }) {
                selection = .topic(id)
            }
        } else if store.activeProjects.contains(where: { $0.id == id }) {
            selection = .project(id)
        }
    }

    private func navigateProject(by delta: Int) {
        let projects = store.activeProjects
        guard !projects.isEmpty else { return }
        let currentIndex: Int
        if case .project(let id) = selection,
           let idx = projects.firstIndex(where: { $0.id == id }) {
            currentIndex = idx
        } else {
            currentIndex = -1
        }
        var newIndex = currentIndex + delta
        newIndex = max(0, min(newIndex, projects.count - 1))
        guard newIndex != currentIndex else { return }
        selection = .project(projects[newIndex].id)
    }

    private func startNewProject() {
        let existing = Set(store.projects.map(\.name))
        let suggestion = discovered.first { !existing.contains($0) } ?? uniqueProjectName(in: existing)
        let reminderLists = ek.reminderListNames(enabled: settings.effectiveReminderListNames)
        let calendars = ek.calendarNames(enabled: settings.effectiveCalendarNames)
        draftProject = ProjectDraft(
            name: suggestion,
            prefix: suggestion,
            reminderListName: defaultName(settings.defaultReminderListName, in: reminderLists),
            calendarName: defaultName(settings.defaultCalendarName, in: calendars),
            weekGoalCalendarName: defaultName(settings.weekGoalCalendarName, in: calendars),
            reminderLists: reminderLists,
            calendars: calendars
        )
    }

    private func uniqueProjectName(in existing: Set<String>) -> String {
        let base = "New Project"
        guard existing.contains(base) else { return base }
        var index = 2
        while existing.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    private func defaultName(_ name: String, in options: [String]) -> String {
        options.contains(name) ? name : (options.first ?? "")
    }

    private func reloadDiscoveredProjects() async {
        discovered = await ek.discoverProjectNames(
            enabledReminderLists: settings.effectiveReminderListNames,
            enabledCalendars: settings.effectiveCalendarNames
        )
    }

    private var tagCloud: some View {
        FlowLayout(spacing: 5, lineSpacing: 5) {
            allChip
            ForEach(sortedDiscoveredTags, id: \.self) { tag in
                tagChip(tag)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var allChip: some View {
        let isActive = tagFilter.isEmpty
        return Button {
            tagFilter.clear()
        } label: {
            Text(L10n.t(.allTags))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? .white : .primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.20), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(L10n.t(.showAllTags))
    }

    private func tagChip(_ tag: String) -> some View {
        let state = tagFilter.state(of: tag)
        let color = settings.tagColor(for: tag)
        return Button {
            tagFilter.cycle(tag)
        } label: {
            HStack(spacing: 3) {
                Text(state == .excluded ? "−" : "#")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(prefixColor(state: state, color: color))
                Text(tag)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(textColor(state: state, color: color))
                    .strikethrough(state == .excluded)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fillColor(state: state, color: color))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(strokeColor(state: state, color: color),
                            style: StrokeStyle(lineWidth: state == .excluded ? 1 : 0.5,
                                               dash: state == .excluded ? [2.5, 2] : []))
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            tagColorMenu(for: tag)
        }
        .help(chipHelp(tag: tag, state: state))
    }

    private func prefixColor(state: TagFilterState, color: Color) -> Color {
        switch state {
        case .included: return Color.white.opacity(0.85)
        case .excluded: return color.opacity(0.85)
        case .neutral:  return color.opacity(0.70)
        }
    }

    private func textColor(state: TagFilterState, color: Color) -> Color {
        switch state {
        case .included: return .white
        case .excluded: return color.opacity(0.60)
        case .neutral:  return .primary
        }
    }

    private func fillColor(state: TagFilterState, color: Color) -> Color {
        switch state {
        case .included: return color
        case .excluded: return color.opacity(0.06)
        case .neutral:  return color.opacity(0.14)
        }
    }

    private func strokeColor(state: TagFilterState, color: Color) -> Color {
        switch state {
        case .included: return color
        case .excluded: return color.opacity(0.55)
        case .neutral:  return color.opacity(0.20)
        }
    }

    /// Tags shared across projects and literature: project-item tag counts
    /// merged with paper tag counts, so the sidebar cloud is one vocabulary.
    private var combinedTags: [String: Int] {
        var aggregate = store.discoveredTags
        // `Paper` is a class, so adding a tag mutates `papers[i].tags` in place and
        // never re-assigns the `papers` array — Observation won't see it. Reading
        // `paperVersion` (bumped on every tag change) ties the cloud to those edits.
        _ = litStore.paperVersion
        for paper in litStore.papers {
            for tag in paper.tags {
                aggregate[tag, default: 0] += 1
            }
        }
        return aggregate
    }

    private func chipHelp(tag: String, state: TagFilterState) -> String {
        let count = combinedTags[tag] ?? 0
        let prefix = "\(tag) · \(count) \(L10n.t(.tagItemsUnit)) — "
        switch state {
        case .neutral:  return prefix + L10n.t(.tagClickInclude)
        case .included: return prefix + L10n.t(.tagClickExclude)
        case .excluded: return prefix + L10n.t(.tagClickClear)
        }
    }

    private var sortedDiscoveredTags: [String] {
        let tags = combinedTags
        return tags.keys.sorted { a, b in
            let ca = tags[a] ?? 0
            let cb = tags[b] ?? 0
            if ca != cb { return ca > cb }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    @ViewBuilder
    private func tagColorMenu(for tag: String) -> some View {
        Menu(L10n.t(.colorMenu)) {
            ForEach(ProjectAppearance.colors) { option in
                Button {
                    settings.setTagColor(tag, colorName: option.id)
                } label: {
                    HStack {
                        Circle().fill(option.color).frame(width: 10, height: 10)
                        Text(option.title)
                        if settings.tagColors[tag] == option.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }

    private func sidebarCreateButton(title: String, systemImage: String,
                                     alignment: HorizontalAlignment,
                                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var persistenceWarning: String? {
        store.persistenceError ?? settings.persistenceError
    }

    private func persistenceWarningView(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption2)
            .foregroundStyle(.orange)
            .lineLimit(3)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(8)
    }
}
