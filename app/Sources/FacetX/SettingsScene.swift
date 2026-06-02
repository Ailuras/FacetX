import SwiftUI

/// The standard macOS Settings window (⌘,). Project management lives in the
/// main window; Settings only contains app-wide container configuration.
struct SettingsRootView: View {
    var body: some View {
        ContainersSettingsView()
            .frame(width: 600, height: 660)
    }
}

private enum SettingsUI {
    static let sectionFont = Font.system(size: 13, weight: .semibold)
    static let rowFont = Font.system(size: 13, weight: .medium)
    static let secondaryFont = Font.system(size: 12)
    static let smallFont = Font.system(size: 11)
    static let controlWidth: CGFloat = 230
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

    // GitHub
    @State private var githubToken = ""
    @State private var githubStatus = ""
    @State private var validating = false

    private var allReminderNames: [String] { names(kind: .reminder) }
    private var allCalendarNames: [String] { names(kind: .calendar) }
    private var enabledReminderNames: [String] {
        allReminderNames.filter { settings.isReminderListEnabled($0) }
    }
    private var enabledCalendarNames: [String] {
        allCalendarNames.filter { settings.isCalendarEnabled($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                summaryStrip
                defaultSaveLocations
                interfaceSection
                containersSection
                createSection
                githubSection
            }
            .padding(20)
        }
        .background(FacetTheme.canvas)
        .onAppear {
            containers = ek.allContainers()
            ensureDefaults()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.13))
                Image(systemName: "switch.2")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.system(size: 20, weight: .semibold))
                Text("Calendar and Reminders")
                    .font(SettingsUI.secondaryFont)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 8) {
            summaryPill(title: "Reminders",
                        value: selectionSummary(enabled: enabledReminderNames.count,
                                                total: allReminderNames.count,
                                                allSelected: settings.enabledReminderListNames.isEmpty),
                        systemImage: "checklist")
            summaryPill(title: "Calendars",
                        value: selectionSummary(enabled: enabledCalendarNames.count,
                                                total: allCalendarNames.count,
                                                allSelected: settings.enabledCalendarNames.isEmpty),
                        systemImage: "calendar")
            summaryPill(title: "Menu Bar",
                        value: settings.menuBarEnabled ? "On" : "Off",
                        systemImage: "menubar.rectangle")
        }
    }

    private func summaryPill(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(SettingsUI.smallFont)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private var defaultSaveLocations: some View {
        settingsCard(title: "Default Save Locations", systemImage: "tray.and.arrow.down") {
            settingRow(title: "Reminders", systemImage: "checklist") {
                Picker("", selection: $settings.defaultReminderListName) {
                    if enabledReminderNames.isEmpty { Text("None").tag("") }
                    ForEach(enabledReminderNames, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: SettingsUI.controlWidth, alignment: .trailing)
            }

            cardDivider

            settingRow(title: "Calendar", systemImage: "calendar") {
                Picker("", selection: $settings.defaultCalendarName) {
                    if enabledCalendarNames.isEmpty { Text("None").tag("") }
                    ForEach(enabledCalendarNames, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: SettingsUI.controlWidth, alignment: .trailing)
            }
        }
    }

    private var interfaceSection: some View {
        settingsCard(title: "Interface", systemImage: "macwindow") {
            settingRow(title: "Show in Menu Bar", systemImage: "menubar.rectangle") {
                Toggle("", isOn: $settings.menuBarEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }

    private var containersSection: some View {
        settingsCard(title: "Containers", systemImage: "square.stack.3d.up") {
            if containers.isEmpty {
                Text("No containers found.")
                    .font(SettingsUI.secondaryFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(compactContainers.enumerated()), id: \.element.id) { index, container in
                        compactContainerRow(container)
                        if index < compactContainers.count - 1 { compactDivider }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .background(FacetTheme.panel.opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                        .stroke(FacetTheme.hairline, lineWidth: 1)
                )
            }
        }
    }

    private var compactContainers: [EventKitService.ContainerInfo] {
        containers.sorted {
            if $0.kind != $1.kind { return $0.kind == .reminder }
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.sourceTitle < $1.sourceTitle
        }
    }

    private func compactContainerRow(_ container: EventKitService.ContainerInfo) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(container.kind == .reminder ? Color.green.opacity(0.12) : Color.blue.opacity(0.12))
                Image(systemName: container.kind == .reminder ? "checklist" : "calendar")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(container.kind == .reminder ? .green : .blue)
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 0) {
                Text(container.title)
                    .font(SettingsUI.rowFont)
                    .lineLimit(1)
                Text("\(container.sourceTitle) · \(container.kind.rawValue)")
                    .font(SettingsUI.smallFont)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isEnabled(container) },
                set: { _ in
                    toggle(container)
                    ensureDefaults()
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.vertical, 5)
    }

    private var compactDivider: some View {
        Divider()
            .opacity(0.36)
            .padding(.leading, 30)
    }

    private var createSection: some View {
        settingsCard(title: "New Container", systemImage: "plus.app") {
            if showCreate {
                createForm
            } else {
                Button { startCreate() } label: {
                    Label("New Container", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
            }
        }
    }

    private var createForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name", text: $newTitle)
                .textFieldStyle(.roundedBorder)

            settingRow(title: "Type", systemImage: "rectangle.split.2x1") {
                Picker("", selection: $newKind) {
                    Text("Reminders").tag(EventKitService.ContainerInfo.Kind.reminder)
                    Text("Calendar").tag(EventKitService.ContainerInfo.Kind.calendar)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: SettingsUI.controlWidth)
            }

            settingRow(title: "Account", systemImage: "person.crop.circle") {
                Picker("", selection: $newSource) {
                    ForEach(sources, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: SettingsUI.controlWidth)
            }

            if let createError {
                Label(createError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { showCreate = false }
                Spacer()
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty || newSource.isEmpty)
            }
            .controlSize(.small)
        }
    }

    private func settingsCard<Content: View>(title: String, systemImage: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(SettingsUI.sectionFont)
                .foregroundStyle(.primary.opacity(0.86))

            content()
        }
        .padding(14)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private func settingRow<Content: View>(title: String, systemImage: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
                .font(SettingsUI.rowFont)
            Spacer()
            content()
        }
        .padding(.vertical, 3)
    }

    private var cardDivider: some View {
        Divider()
            .opacity(0.42)
            .padding(.leading, 28)
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
        let result = ek.createContainer(title: title, kind: newKind, sourceTitle: newSource)
        if result.ok {
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
            createError = result.error ?? "Couldn't create in \(newSource)."
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

    private func selectionSummary(enabled: Int, total: Int, allSelected: Bool) -> String {
        guard total > 0 else { return "None" }
        return allSelected ? "All \(total)" : "\(enabled)/\(total)"
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

    // MARK: – GitHub

    private var githubSection: some View {
        settingsCard(title: "GitHub", systemImage: "curlybraces") {
            VStack(alignment: .leading, spacing: 10) {
                if githubStatus.isEmpty {
                    Text("No token configured.")
                        .font(SettingsUI.secondaryFont)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(githubStatus)
                            .font(SettingsUI.secondaryFont)
                    }
                }

                SecureField("Personal Access Token", text: $githubToken)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    if !githubStatus.isEmpty {
                        Button("Remove Token") {
                            GitHubTokenStore.deleteToken()
                            githubToken = ""
                            githubStatus = ""
                        }
                        .controlSize(.small)
                    }
                    Spacer()
                    Button(validating ? "Validating…" : "Save Token") {
                        saveGitHubToken()
                    }
                    .controlSize(.small)
                    .disabled(githubToken.isEmpty || validating)
                }
            }
        }
        .onAppear { loadGitHubStatus() }
    }

    private func loadGitHubStatus() {
        if let token = GitHubTokenStore.loadToken() {
            githubToken = token
            Task {
                do {
                    let username = try await GitHubService().validateToken(token)
                    await MainActor.run {
                        githubStatus = "Connected as \(username)"
                    }
                } catch {
                    await MainActor.run {
                        githubStatus = "Token invalid"
                    }
                }
            }
        }
    }

    private func saveGitHubToken() {
        let token = githubToken.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { return }
        validating = true
        Task {
            do {
                let username = try await GitHubService().validateToken(token)
                GitHubTokenStore.saveToken(token)
                await MainActor.run {
                    githubStatus = "Connected as \(username)"
                    validating = false
                }
            } catch {
                await MainActor.run {
                    githubStatus = "Validation failed"
                    validating = false
                }
            }
        }
    }
}
