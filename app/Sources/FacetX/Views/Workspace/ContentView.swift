import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    enum SidebarItem: Hashable { case today, project(Project.ID) }

    @State private var selection: SidebarItem? = .today
    @State private var discovered: [String] = []
    @State private var draftProject: ProjectDraft?
    @State private var editingProject: Project?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                if let persistenceWarning {
                    persistenceWarningView(persistenceWarning)
                }
                List(selection: $selection) {
                    Section {
                        Label("Today", systemImage: "sun.max.fill")
                            .tag(SidebarItem.today)
                    }
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
                                    }
                                    Button("Delete", role: .destructive) {
                                        store.delete(project)
                                    }
                                }
                        }
                        .onMove { indices, newOffset in
                            store.reorderProjects(from: indices, to: newOffset)
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
            switch selection {
            case .today, nil:
                TodayView(onOpenProject: { selection = .project($0) })
            case .project(let id):
                if let project = store.activeProjects.first(where: { $0.id == id }) {
                    ProjectDetailView(project: project)
                } else {
                    ContentUnavailableView("Select a project",
                        systemImage: "folder",
                        description: Text("Pick a project from the sidebar."))
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { selection = .today }
        .task {
            if !ek.remindersAuthorized && !ek.calendarAuthorized {
                await ek.requestAccess()
            }
            await reloadDiscoveredProjects()
        }
        .onChange(of: settings.changeToken) { Task { await reloadDiscoveredProjects() } }
        .sheet(item: $draftProject) { draft in
            NewProjectView(draft: draft) { name, prefix, tagline, reminderList, calendar, goalCalendar, githubRepo in
                let id = store.createProject(name: name, prefix: prefix, tagline: tagline,
                                              reminderListName: reminderList, calendarName: calendar,
                                              weekGoalCalendarName: goalCalendar,
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
