import SwiftUI

/// Settings: choose which calendars / reminder lists DocsBot reads and writes.
/// Selection is stored by container *title* (stable across devices), so the
/// same config works on multiple Macs even with different Apple accounts.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var settings: Settings

    @State private var containers: [EventKitService.ContainerInfo] = []

    // New-container form state
    @State private var showCreate = false
    @State private var newTitle = ""
    @State private var newKind: EventKitService.ContainerInfo.Kind = .reminder
    @State private var newSource = ""
    @State private var sources: [String] = []
    @State private var createError: String?

    /// Group by "Account · Kind" for display.
    private var groups: [(header: String, items: [EventKitService.ContainerInfo])] {
        Dictionary(grouping: containers) { "\($0.sourceTitle) · \($0.kind.rawValue)" }
            .map { ($0.key, $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.header < $1.header }
    }

    private var allNames: [String] { containers.map(\.title) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Containers").font(.title2).bold()
            Text("Choose which calendars and reminder lists DocsBot uses. "
                 + "Selection is matched by name, so it stays consistent across your Macs.")
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
                            )) {
                                Text(c.title)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 280)

            if showCreate { createForm } else {
                Button { startCreate() } label: {
                    Label("New list or calendar…", systemImage: "plus")
                }
            }

            HStack {
                Button("Use all") { settings.enabledContainerNames = [] }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: showCreate ? 600 : 480)
        .onAppear { containers = ek.allContainers() }
    }

    /// Inline form to create a container that doesn't exist yet — so the tool
    /// works for someone whose calendar lacks the expected lists.
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
            settings.enable(title)   // keep it visible if a filter is active
            newTitle = ""
            showCreate = false
        } else {
            createError = "Couldn't create in \(newSource)."
        }
    }
}
