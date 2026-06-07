import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var keyboard: KeyboardActionRouter
    @EnvironmentObject private var toast: ToastController

    enum SidebarItem: Hashable { case project(Project.ID) }

    @State private var selection: SidebarItem? = nil
    @State private var selectedTag: String? = nil
    @State private var showTodayPanel = false
    @State private var discovered: [String] = []
    @State private var draftProject: ProjectDraft?
    @State private var editingProject: Project?
    @State private var projectToDelete: Project?

    var body: some View {
        ZStack {
            NavigationSplitView {
                VStack(spacing: 0) {
                    if let persistenceWarning {
                        persistenceWarningView(persistenceWarning)
                    }
                    List(selection: $selection) {
                        Section("Projects") {
                            ForEach(store.activeProjects) { project in
                                ProjectSidebarRow(project: project)
                                    .tag(SidebarItem.project(project.id))
                                    .contextMenu {
                                        Button("Edit Project") {
                                            selection = .project(project.id)
                                            editingProject = project
                                        }
                                        Divider()
                                        Button("Archive") {
                                            store.archive(project)
                                            toast.show("Project archived", type: .info)
                                        }
                                        Button("Delete", role: .destructive) {
                                            projectToDelete = project
                                        }
                                    }
                            }
                            .onMove { indices, newOffset in
                                store.reorderProjects(from: indices, to: newOffset)
                            }
                        }
                        if !sortedDiscoveredTags.isEmpty {
                            Section("Tags") {
                                ForEach(sortedDiscoveredTags, id: \.self) { tag in
                                    tagRow(tag)
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    Divider()
                    Button { startNewProject() } label: {
                        Label("New Project", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary.opacity(0.82))
                    .padding(8)
                }
                .navigationTitle("FacetX")
            } detail: {
                HStack(spacing: 0) {
                    Group {
                        switch selection {
                        case nil:
                            ContentUnavailableView(
                                "Select a project",
                                systemImage: "folder",
                                description: Text("Pick a project from the sidebar to get started.")
                            )
                        case .project(let id):
                            if let project = store.activeProjects.first(where: { $0.id == id }) {
                                ProjectDetailView(project: project, showTodayPanel: $showTodayPanel, selectedTag: $selectedTag)
                            } else {
                                ContentUnavailableView("Project not found", systemImage: "folder")
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
            .task {
                keyboard.registerLocalShortcuts()
                if !ek.remindersAuthorized && !ek.calendarAuthorized {
                    await ek.requestAccess()
                    // Show banner if access was denied
                    if !ek.remindersAuthorized && !ek.calendarAuthorized {
                        toast.showBanner(
                            "Calendar and Reminders access is required to display items.",
                            type: .warning,
                            action: BannerAction(title: "Open Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                            }
                        )
                    }
                }
                await reloadDiscoveredProjects()
            }
            .onChange(of: settings.changeToken) { Task { await reloadDiscoveredProjects() } }
            .alert("Delete project?", isPresented: .init(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { projectToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let project = projectToDelete {
                        store.delete(project)
                        toast.show("Project deleted", type: .success)
                    }
                    projectToDelete = nil
                }
            } message: {
                Text("“\(projectToDelete?.name ?? "")” will be removed. Its items remain in Calendar/Reminders.")
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

    private func tagRow(_ tag: String) -> some View {
        let isSel = selectedTag == tag
        let color = settings.tagColor(for: tag)
        return TagSidebarRow(
            tag: tag,
            count: store.discoveredTags[tag] ?? 0,
            color: color,
            isSelected: isSel
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedTag = isSel ? nil : tag
        }
        .contextMenu {
            tagColorMenu(for: tag)
        }
    }

    private var sortedDiscoveredTags: [String] {
        store.discoveredTags.keys.sorted { a, b in
            let ca = store.discoveredTags[a] ?? 0
            let cb = store.discoveredTags[b] ?? 0
            if ca != cb { return ca > cb }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    @ViewBuilder
    private func tagColorMenu(for tag: String) -> some View {
        Menu("Color") {
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
