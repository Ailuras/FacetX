import SwiftUI

/// The standard macOS Settings window (⌘,). Project management lives in the
/// main window; Settings only contains app-wide container configuration.
struct SettingsRootView: View {
    var body: some View {
        ContainersSettingsView()
            .frame(width: 520, height: 560)
    }
}

// ── Containers ───────────────────────────────────────────────────────────────

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
    private var enabledReminderNames: [String] {
        names(kind: .reminder).filter { settings.isEnabled($0) }
    }
    private var enabledCalendarNames: [String] {
        names(kind: .calendar).filter { settings.isEnabled($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Containers", systemImage: "calendar")
                    .font(.title3).fontWeight(.semibold)
                Spacer()
                Button("Use All") {
                    settings.enabledContainerNames = []
                    ensureDefaults()
                }
            }

            Text("Choose which calendars and reminder lists FacetX uses. "
                 + "Matched by name, so it stays consistent across your Macs.")
                .font(.caption).foregroundStyle(.secondary)

            if settings.enabledContainerNames.isEmpty {
                Label("All containers are in use (nothing excluded yet).",
                      systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Default save locations")
                    .font(.headline)
                Picker("Reminders", selection: $settings.defaultReminderListName) {
                    if enabledReminderNames.isEmpty { Text("None").tag("") }
                    ForEach(enabledReminderNames, id: \.self) { Text($0).tag($0) }
                }
                Picker("Calendar", selection: $settings.defaultCalendarName) {
                    if enabledCalendarNames.isEmpty { Text("None").tag("") }
                    ForEach(enabledCalendarNames, id: \.self) { Text($0).tag($0) }
                }
            }

            List {
                ForEach(groups, id: \.header) { group in
                    Section(group.header) {
                        ForEach(group.items) { c in
                            Toggle(isOn: Binding(
                                get: { settings.isEnabled(c.title) },
                                set: { _ in
                                    settings.toggle(c.title, allNames: allNames)
                                    ensureDefaults()
                                }
                            )) { Text(c.title) }
                        }
                    }
                }
            }

            if showCreate { createForm } else {
                Button { startCreate() } label: {
                    Label("New Container", systemImage: "plus")
                }
            }
        }
        .padding(16)
        .onAppear {
            containers = ek.allContainers()
            ensureDefaults()
        }
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
            if newKind == .reminder, settings.defaultReminderListName.isEmpty {
                settings.defaultReminderListName = title
            }
            if newKind == .calendar, settings.defaultCalendarName.isEmpty {
                settings.defaultCalendarName = title
            }
            newTitle = ""
            showCreate = false
        } else {
            createError = "Couldn't create in \(newSource)."
        }
    }

    private func names(kind: EventKitService.ContainerInfo.Kind) -> [String] {
        Array(Set(containers.filter { $0.kind == kind }.map(\.title))).sorted()
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
    }
}
