import SwiftUI

/// The standard macOS Settings window (⌘,). Groups all *configuration* — the
/// main window and menu bar are for *use*, not setup.
struct SettingsRootView: View {
    var body: some View {
        TabView {
            ProjectsSettingsView()
                .tabItem { Label("Projects", systemImage: "folder") }
            ContainersSettingsView()
                .tabItem { Label("Containers", systemImage: "calendar") }
        }
        .frame(width: 480, height: 520)
    }
}

// ── Projects tab ─────────────────────────────────────────────────────────────

/// Declare and manage projects: name, prefix, tagline, archive/delete. This is
/// configuration, so it lives here rather than in the main window.
struct ProjectsSettingsView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var ek: EventKitService

    @State private var selectedID: Project.ID?
    @State private var discovered: [String] = []
    @State private var draftProject: ProjectDraft?

    private var selected: Project? {
        store.projects.first { $0.id == selectedID }
    }

    var body: some View {
        HSplitView {
            // Left: project list + declare
            VStack(spacing: 0) {
                List(selection: $selectedID) {
                    ForEach(store.projects) { p in
                        HStack {
                            Text(p.name)
                            if p.archived {
                                Text("archived").font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(p.id)
                    }
                }
                Divider()
                Button { startDeclare() } label: {
                    Label("Declare project", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .padding(8)
            }
            .frame(minWidth: 160)

            // Right: editor for the selected project
            Group {
                if let project = selected {
                    ProjectEditor(project: project)
                        .id(project.id)
                } else {
                    Text("Select a project, or declare a new one.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 280)
        }
        .task {
            discovered = await ek.discoverProjectNames()
        }
        .sheet(item: $draftProject) { draft in
            DeclareProjectView(draft: draft) { name, prefix, tagline in
                let id = store.declare(name: name, prefix: prefix, tagline: tagline)
                selectedID = id
                draftProject = nil
            } onCancel: {
                draftProject = nil
            }
        }
    }

    private func startDeclare() {
        // Offer the first undeclared discovered prefix as a starting name.
        let existing = Set(store.projects.map(\.name))
        let suggestion = discovered.first { !existing.contains($0) } ?? "New Project"
        draftProject = ProjectDraft(name: suggestion, prefix: suggestion)
    }
}

private struct ProjectDraft: Identifiable {
    let id = UUID()
    var name: String
    var prefix: String
    var tagline = ""
}

private struct DeclareProjectView: View {
    let draft: ProjectDraft
    let onCreate: (String, String?, String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var prefix: String
    @State private var tagline: String

    init(draft: ProjectDraft,
         onCreate: @escaping (String, String?, String) -> Void,
         onCancel: @escaping () -> Void) {
        self.draft = draft
        self.onCreate = onCreate
        self.onCancel = onCancel
        _name = State(initialValue: draft.name)
        _prefix = State(initialValue: draft.prefix)
        _tagline = State(initialValue: draft.tagline)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Declare project").font(.title2).bold()

            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                    TextField("Prefix (matches “Prefix:” in titles)", text: $prefix)
                    Text("Items whose title starts with “\(effectivePrefix):” belong to this project.")
                        .font(.caption2).foregroundStyle(.secondary)
                    TextField("Tagline", text: $tagline)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedPrefix: String {
        prefix.trimmingCharacters(in: .whitespaces)
    }

    private var effectivePrefix: String {
        trimmedPrefix.isEmpty ? (trimmedName.isEmpty ? "..." : trimmedName) : trimmedPrefix
    }

    private func create() {
        let prefix = trimmedPrefix.isEmpty ? nil : trimmedPrefix
        onCreate(trimmedName, prefix, tagline.trimmingCharacters(in: .whitespaces))
    }
}

/// Editor for a single project's configuration.
struct ProjectEditor: View {
    @EnvironmentObject private var store: ProjectStore
    let project: Project

    @State private var name = ""
    @State private var prefix = ""
    @State private var tagline = ""
    @State private var loaded = false

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $name)
                TextField("Prefix (matches “Prefix:” in titles)", text: $prefix)
                Text("Items whose title starts with “\(prefix.isEmpty ? "…" : prefix):” belong to this project.")
                    .font(.caption2).foregroundStyle(.secondary)
                TextField("Tagline", text: $tagline)
            }
            Section {
                HStack {
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                    Spacer()
                    if project.archived {
                        Button("Unarchive") { unarchive() }
                    } else {
                        Button("Archive") { store.archive(project) }
                    }
                    Button("Delete", role: .destructive) { store.delete(project) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadFields)
    }

    private func loadFields() {
        name = project.name
        prefix = project.prefix
        tagline = project.tagline
        loaded = true
    }

    private func save() {
        var p = project
        p.name = name.trimmingCharacters(in: .whitespaces)
        p.prefix = prefix.trimmingCharacters(in: .whitespaces).isEmpty
            ? p.name : prefix.trimmingCharacters(in: .whitespaces)
        p.tagline = tagline.trimmingCharacters(in: .whitespaces)
        guard !p.name.isEmpty else { return }
        store.update(p)
    }

    private func unarchive() {
        var p = project
        p.archived = false
        store.update(p)
    }
}

// ── Containers tab ───────────────────────────────────────────────────────────

/// Choose which calendars / reminder lists FacetX reads and writes; create new
/// ones if the expected lists are missing. Stored by title (device-stable).
struct ContainersSettingsView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var settings: AppSettings

    @State private var containers: [EventKitService.ContainerInfo] = []

    @State private var showCreate = false
    @State private var newTitle = ""
    @State private var newKind: EventKitService.ContainerInfo.Kind = .reminder
    @State private var newSource = ""
    @State private var sources: [String] = []
    @State private var createError: String?

    private var groups: [(header: String, items: [EventKitService.ContainerInfo])] {
        Dictionary(grouping: containers) { "\($0.sourceTitle) · \($0.kind.rawValue)" }
            .map { ($0.key, $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.header < $1.header }
    }

    private var allNames: [String] { containers.map(\.title) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose which calendars and reminder lists FacetX uses. "
                 + "Matched by name, so it stays consistent across your Macs.")
                .font(.caption).foregroundStyle(.secondary)

            if settings.enabledContainerNames.isEmpty {
                Label("All containers are in use (nothing excluded yet).",
                      systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }

            List {
                ForEach(groups, id: \.header) { group in
                    Section(group.header) {
                        ForEach(group.items) { c in
                            Toggle(isOn: Binding(
                                get: { settings.isEnabled(c.title) },
                                set: { _ in settings.toggle(c.title, allNames: allNames) }
                            )) { Text(c.title) }
                        }
                    }
                }
            }

            if showCreate { createForm } else {
                Button { startCreate() } label: {
                    Label("New list or calendar…", systemImage: "plus")
                }
            }

            Button("Use all") { settings.enabledContainerNames = [] }
        }
        .padding(16)
        .onAppear { containers = ek.allContainers() }
    }

    private var createForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("New container").font(.headline)
            TextField("Name (e.g. 科研待办)", text: $newTitle).textFieldStyle(.roundedBorder)
            Picker("Type", selection: $newKind) {
                Text("Reminders list").tag(EventKitService.ContainerInfo.Kind.reminder)
                Text("Calendar").tag(EventKitService.ContainerInfo.Kind.calendar)
            }
            .pickerStyle(.segmented)
            .onChange(of: newKind) { _, _ in reloadSources() }
            Picker("Account", selection: $newSource) {
                ForEach(sources, id: \.self) { Text($0).tag($0) }
            }
            if let createError { Text(createError).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { showCreate = false }
                Spacer()
                Button("Create") { create() }
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty || newSource.isEmpty)
            }
        }
    }

    private func startCreate() {
        showCreate = true
        createError = nil
        reloadSources()
    }

    private func reloadSources() {
        sources = ek.sourceTitles(forNew: newKind)
        if !sources.contains(newSource) { newSource = sources.first ?? "" }
    }

    private func create() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, !newSource.isEmpty else { return }
        if ek.createContainer(title: title, kind: newKind, sourceTitle: newSource) {
            containers = ek.allContainers()
            settings.enable(title)
            newTitle = ""
            showCreate = false
        } else {
            createError = "Couldn't create in \(newSource)."
        }
    }
}
