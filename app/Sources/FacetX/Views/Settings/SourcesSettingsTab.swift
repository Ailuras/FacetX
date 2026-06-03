import SwiftUI

struct SourcesSettingsTab: View {
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
