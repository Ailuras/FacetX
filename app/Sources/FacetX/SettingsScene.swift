import SwiftUI

/// The standard macOS Settings window (⌘,), organized by function instead of a
/// single long page. Project management still lives in the main window.
struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            DefaultsSettingsTab()
                .tabItem { Label("Defaults", systemImage: "tray.and.arrow.down") }
            SourcesSettingsTab()
                .tabItem { Label("Sources", systemImage: "square.stack.3d.up") }
            IntegrationsSettingsTab()
                .tabItem { Label("Integrations", systemImage: "curlybraces") }
        }
        .frame(width: 720, height: 600)
    }
}

private enum SettingsUI {
    static let sectionFont = Font.system(size: 13, weight: .semibold)
    static let rowFont = Font.system(size: 13, weight: .medium)
    static let secondaryFont = Font.system(size: 12)
    static let smallFont = Font.system(size: 11)
    static let controlWidth: CGFloat = 230
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SettingsPage(title: "General",
                     subtitle: "Interface and local state",
                     systemImage: "gearshape",
                     warning: persistenceWarning) {
            SettingsCard(title: "Interface", systemImage: "macwindow") {
                SettingsRow(title: "Show in Menu Bar", systemImage: "menubar.rectangle") {
                    Toggle("", isOn: $settings.menuBarEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
            }

            SettingsCard(title: "Storage", systemImage: "externaldrive") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Application Support")
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
}

// MARK: - Defaults

private struct DefaultsSettingsTab: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    private var enabledReminderNames: [String] {
        ek.reminderListNames(enabled: settings.effectiveReminderListNames)
    }

    private var enabledCalendarNames: [String] {
        ek.calendarNames(enabled: settings.effectiveCalendarNames)
    }

    var body: some View {
        SettingsPage(title: "Defaults",
                     subtitle: "Where new project data is saved",
                     systemImage: "tray.and.arrow.down",
                     warning: persistenceWarning) {
            SettingsCard(title: "Project Items", systemImage: "tray.and.arrow.down") {
                SettingsRow(title: "Reminders", systemImage: "checklist") {
                    Picker("", selection: $settings.defaultReminderListName) {
                        if enabledReminderNames.isEmpty { Text("None").tag("") }
                        ForEach(enabledReminderNames, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: SettingsUI.controlWidth, alignment: .trailing)
                }

                SettingsDivider()

                SettingsRow(title: "Calendar", systemImage: "calendar") {
                    Picker("", selection: $settings.defaultCalendarName) {
                        if enabledCalendarNames.isEmpty { Text("None").tag("") }
                        ForEach(enabledCalendarNames, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: SettingsUI.controlWidth, alignment: .trailing)
                }

                SettingsDivider()

                SettingsRow(title: "Event Duration", systemImage: "clock") {
                    HStack(spacing: 8) {
                        Text("\(settings.defaultEventDurationMinutes) min")
                            .font(SettingsUI.secondaryFont)
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .trailing)
                        Stepper("", value: $settings.defaultEventDurationMinutes, in: 5...1440, step: 15)
                            .labelsHidden()
                    }
                    .frame(width: SettingsUI.controlWidth, alignment: .trailing)
                }
            }

            SettingsCard(title: "Week Goals", systemImage: "target") {
                SettingsRow(title: "Calendar", systemImage: "calendar.badge.clock") {
                    Picker("", selection: $settings.weekGoalCalendarName) {
                        if enabledCalendarNames.isEmpty { Text("None").tag("") }
                        ForEach(enabledCalendarNames, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: SettingsUI.controlWidth, alignment: .trailing)
                }

                Text("Week goals are all-day calendar events shared across projects. They are kept out of normal project item lists.")
                    .font(SettingsUI.secondaryFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: ensureDefaults)
        .onChange(of: settings.changeToken) { ensureDefaults() }
    }

    private var persistenceWarning: String? {
        store.persistenceError ?? settings.persistenceError
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
        if settings.weekGoalCalendarName.isEmpty
            || !enabledCalendarNames.contains(settings.weekGoalCalendarName) {
            settings.weekGoalCalendarName = settings.defaultCalendarName.isEmpty
                ? (enabledCalendarNames.first ?? "")
                : settings.defaultCalendarName
        }
        if settings.defaultEventDurationMinutes < 5 {
            settings.defaultEventDurationMinutes = 5
        } else if settings.defaultEventDurationMinutes > 1440 {
            settings.defaultEventDurationMinutes = 1440
        }
    }
}

// MARK: - Sources

private struct SourcesSettingsTab: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    @State private var containers: [EventKitService.ContainerInfo] = []

    private var allReminderNames: [String] { names(kind: .reminder) }
    private var allCalendarNames: [String] { names(kind: .calendar) }
    private var enabledReminderNames: [String] {
        allReminderNames.filter { settings.isReminderListEnabled($0) }
    }
    private var enabledCalendarNames: [String] {
        allCalendarNames.filter { settings.isCalendarEnabled($0) }
    }

    var body: some View {
        SettingsPage(title: "Sources",
                     subtitle: "Calendar and Reminders containers",
                     systemImage: "square.stack.3d.up",
                     warning: persistenceWarning) {
            summaryStrip

            if !duplicateContainerWarnings.isEmpty {
                duplicateContainersSection
            }

            containersSection
        }
        .onAppear(perform: reloadContainers)
        .onChange(of: ek.changeToken) { reloadContainers() }
    }

    private var persistenceWarning: String? {
        store.persistenceError ?? settings.persistenceError
    }

    private var summaryStrip: some View {
        HStack(spacing: 8) {
            SummaryPill(title: "Reminders",
                        value: selectionSummary(enabled: enabledReminderNames.count,
                                                total: allReminderNames.count,
                                                allSelected: !settings.reminderListsDisabled && settings.enabledReminderListNames.isEmpty,
                                                allDisabled: settings.reminderListsDisabled),
                        systemImage: "checklist")
            SummaryPill(title: "Calendars",
                        value: selectionSummary(enabled: enabledCalendarNames.count,
                                                total: allCalendarNames.count,
                                                allSelected: !settings.calendarsDisabled && settings.enabledCalendarNames.isEmpty,
                                                allDisabled: settings.calendarsDisabled),
                        systemImage: "calendar")

            VStack(spacing: 6) {
                sourceActionButton(title: "Use All", systemImage: "checkmark.circle") {
                    settings.useAllContainers()
                    ensureDefaults()
                }
                sourceActionButton(title: "Disable All", systemImage: "xmark.circle") {
                    settings.disableAllContainers()
                    ensureDefaults()
                }
            }
            .frame(width: 118)
        }
    }

    private func sourceActionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(SettingsUI.smallFont.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private var containersSection: some View {
        SettingsCard(title: "Enabled Sources", systemImage: "square.stack.3d.up") {
            if containers.isEmpty {
                Text("No containers found.")
                    .font(SettingsUI.secondaryFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    containerColumn(kind: .reminder, title: "Reminders", icon: "checklist", color: .green)
                    containerColumn(kind: .calendar, title: "Calendars", icon: "calendar", color: .blue)
                }
            }
        }
    }

    private var duplicateContainersSection: some View {
        SettingsCard(title: "Duplicate Names", systemImage: "exclamationmark.triangle") {
            VStack(alignment: .leading, spacing: 8) {
                Text("FacetX stores container selections by title. Duplicate names below are enabled, disabled, and chosen as save targets together.")
                    .font(SettingsUI.secondaryFont)
                    .foregroundStyle(.secondary)

                ForEach(Array(duplicateContainerWarnings.enumerated()), id: \.offset) { _, warning in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: warning.kind == .reminder ? "checklist" : "calendar")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(warning.kind == .reminder ? .green : .blue)
                            .frame(width: 16)
                        Text("\(warning.title) appears in \(warning.sources.joined(separator: ", ")). Rename one if you need exact control.")
                            .font(SettingsUI.secondaryFont)
                            .foregroundStyle(.primary.opacity(0.82))
                    }
                }
            }
        }
    }

    private func containerColumn(kind: EventKitService.ContainerInfo.Kind,
                                 title: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)

            let filtered = compactContainers.filter { $0.kind == kind }
            if filtered.isEmpty {
                Text("None")
                    .font(SettingsUI.smallFont)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FacetTheme.panel.opacity(0.42))
                    .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                            .stroke(FacetTheme.hairline, lineWidth: 1)
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, container in
                        compactContainerRow(container)
                        if index < filtered.count - 1 { compactDivider }
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 0) {
                Text(container.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(container.sourceTitle)
                    .font(.system(size: 10))
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
            .controlSize(.mini)
        }
        .padding(.vertical, 4)
    }

    private var compactDivider: some View {
        Divider()
            .opacity(0.36)
            .padding(.leading, 30)
    }

    private var compactContainers: [EventKitService.ContainerInfo] {
        containers.sorted {
            if $0.kind != $1.kind { return $0.kind == .reminder }
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.sourceTitle < $1.sourceTitle
        }
    }

    private var duplicateContainerWarnings: [(kind: EventKitService.ContainerInfo.Kind, title: String, sources: [String])] {
        let grouped = Dictionary(grouping: containers) { container in
            "\(container.kind.rawValue)/\(container.title)"
        }
        return grouped.compactMap { _, matches in
            guard matches.count > 1, let first = matches.first else { return nil }
            let sources = matches.map(\.sourceTitle).sorted()
            return (kind: first.kind, title: first.title, sources: sources)
        }
        .sorted {
            if $0.kind != $1.kind { return $0.kind == .reminder }
            return $0.title < $1.title
        }
    }

    private func reloadContainers() {
        containers = ek.allContainers()
        ensureDefaults()
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

    private func selectionSummary(enabled: Int, total: Int, allSelected: Bool, allDisabled: Bool) -> String {
        guard total > 0 else { return "None" }
        if allDisabled { return "0/\(total)" }
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
        if settings.weekGoalCalendarName.isEmpty
            || !enabledCalendarNames.contains(settings.weekGoalCalendarName) {
            settings.weekGoalCalendarName = settings.defaultCalendarName.isEmpty
                ? (enabledCalendarNames.first ?? "")
                : settings.defaultCalendarName
        }
    }
}

// MARK: - Integrations

private struct IntegrationsSettingsTab: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    @State private var githubToken = ""
    @State private var githubStatus = ""
    @State private var validating = false

    var body: some View {
        SettingsPage(title: "Integrations",
                     subtitle: "External services and credentials",
                     systemImage: "curlybraces",
                     warning: persistenceWarning) {
            SettingsCard(title: "GitHub", systemImage: "curlybraces") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if githubStatus.isEmpty {
                            Text("No token configured.")
                                .font(SettingsUI.secondaryFont)
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: githubConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(githubConnected ? .green : .orange)
                                Text(githubStatus)
                                    .font(SettingsUI.secondaryFont)
                            }
                        }

                        Spacer()

                        if !githubStatus.isEmpty {
                            Button("Remove") {
                                settings.githubToken = ""
                                githubToken = ""
                                githubStatus = ""
                            }
                            .controlSize(.small)
                        }
                    }

                    HStack(spacing: 8) {
                        SecureField("Personal Access Token", text: $githubToken)
                            .textFieldStyle(.roundedBorder)

                        Button(validating ? "Validating..." : "Save") {
                            saveGitHubToken()
                        }
                        .disabled(githubToken.isEmpty || validating)
                    }
                }
            }
        }
        .onAppear(perform: loadGitHubStatus)
    }

    private var persistenceWarning: String? {
        store.persistenceError ?? settings.persistenceError
    }

    private var githubConnected: Bool {
        githubStatus.hasPrefix("Connected as ")
    }

    private func loadGitHubStatus() {
        let token = settings.githubToken
        guard githubToken.isEmpty, !token.isEmpty else { return }
        githubToken = token
        Task {
            do {
                let username = try await GitHubService().validateToken(token)
                await MainActor.run { githubStatus = "Connected as \(username)" }
            } catch {
                await MainActor.run { githubStatus = "Token invalid" }
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
                await MainActor.run {
                    settings.githubToken = token
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

// MARK: - Shared Settings UI

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let warning: String?
    let content: () -> Content

    init(title: String, subtitle: String, systemImage: String, warning: String?,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.warning = warning
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let warning {
                    persistenceWarningView(warning)
                }
                content()
            }
            .padding(20)
        }
        .background(FacetTheme.canvas)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.13))
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                Text(subtitle)
                    .font(SettingsUI.secondaryFont)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func persistenceWarningView(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(SettingsUI.secondaryFont)
            .foregroundStyle(.orange)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                    .stroke(Color.orange.opacity(0.24), lineWidth: 1)
            )
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: () -> Content

    init(title: String, systemImage: String,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
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
}

private struct SettingsRow<Content: View>: View {
    let title: String
    let systemImage: String
    let content: () -> Content

    init(title: String, systemImage: String,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
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
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .opacity(0.42)
            .padding(.leading, 28)
    }
}

private struct SummaryPill: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
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
}
