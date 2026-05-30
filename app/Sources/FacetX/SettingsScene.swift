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
/// ones if the expected lists are missing. Stored by title within each type
/// (device-stable, without coupling same-title calendars and reminder lists).
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

    private var allReminderNames: [String] { names(kind: .reminder) }
    private var allCalendarNames: [String] { names(kind: .calendar) }
    private var enabledReminderNames: [String] {
        allReminderNames.filter { settings.isReminderListEnabled($0) }
    }
    private var enabledCalendarNames: [String] {
        allCalendarNames.filter { settings.isCalendarEnabled($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Containers", systemImage: "calendar")
                    .font(.title3).fontWeight(.semibold)
                Spacer()
                Button("Use All") {
                    settings.useAllContainers()
                    ensureDefaults()
                }
            }

            Text("Choose which calendars and reminder lists FacetX uses. "
                 + "Matched by type and name, so same-title lists and calendars stay independent.")
                .font(.caption).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Interface")
                    .font(.headline)
                Toggle("Show in Menu Bar", isOn: $settings.menuBarEnabled)
            }

            if settings.enabledReminderListNames.isEmpty && settings.enabledCalendarNames.isEmpty {
                Label("All containers are in use (nothing excluded yet).",
                      systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }

            defaultSaveLocations

            List {
                ForEach(groups, id: \.header) { group in
                    Section(group.header) {
                        ForEach(group.items) { c in
                            Toggle(isOn: Binding(
                                get: { isEnabled(c) },
                                set: { _ in
                                    toggle(c)
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

    private var defaultSaveLocations: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default save locations")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Reminders")
                        .frame(width: 82, alignment: .leading)
                    Picker("", selection: $settings.defaultReminderListName) {
                        if enabledReminderNames.isEmpty { Text("None").tag("") }
                        ForEach(enabledReminderNames, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 190, alignment: .leading)
                }

                GridRow {
                    Text("Calendar")
                        .frame(width: 82, alignment: .leading)
                    Picker("", selection: $settings.defaultCalendarName) {
                        if enabledCalendarNames.isEmpty { Text("None").tag("") }
                        ForEach(enabledCalendarNames, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 190, alignment: .leading)
                }
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
            if newKind == .reminder {
                settings.enableReminderList(title)
            } else {
                settings.enableCalendar(title)
            }
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

    private func isEnabled(_ container: EventKitService.ContainerInfo) -> Bool {
        switch container.kind {
        case .reminder:
            return settings.isReminderListEnabled(container.title)
        case .calendar:
            return settings.isCalendarEnabled(container.title)
        }
    }

    private func toggle(_ container: EventKitService.ContainerInfo) {
        switch container.kind {
        case .reminder:
            settings.toggleReminderList(container.title, allNames: allReminderNames)
        case .calendar:
            settings.toggleCalendar(container.title, allNames: allCalendarNames)
        }
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
