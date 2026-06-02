import SwiftUI

struct ProjectDraft: Identifiable {
    let id = UUID()
    var name: String
    var prefix: String
    var tagline = ""
    var reminderListName: String
    var calendarName: String
    var githubRepo: String = ""
    var reminderLists: [String]
    var calendars: [String]
}

struct NewProjectView: View {
    let draft: ProjectDraft
    let onCreate: (String, String?, String, String?, String?, String?) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var prefix: String
    @State private var tagline: String
    @State private var reminderListName: String
    @State private var calendarName: String
    @State private var githubRepo: String

    init(draft: ProjectDraft,
         onCreate: @escaping (String, String?, String, String?, String?, String?) -> Void,
         onCancel: @escaping () -> Void) {
        self.draft = draft
        self.onCreate = onCreate
        self.onCancel = onCancel
        _name = State(initialValue: draft.name)
        _prefix = State(initialValue: draft.prefix)
        _tagline = State(initialValue: draft.tagline)
        _reminderListName = State(initialValue: draft.reminderListName)
        _calendarName = State(initialValue: draft.calendarName)
        _githubRepo = State(initialValue: draft.githubRepo)
    }

    var body: some View {
        VStack(spacing: 0) {
            ProjectEditorHeader(title: "New Project",
                                subtitle: "Create a facet over Calendar and Reminders",
                                initial: projectInitial)
            Divider().opacity(0.7)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    identityCard
                    saveLocationsCard
                    integrationsCard
                }
                .padding(18)
            }

            Divider().opacity(0.7)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .controlSize(.small)
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || reminderListName.isEmpty || calendarName.isEmpty)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(FacetTheme.canvas)
        .frame(width: 500, height: 560)
    }

    private var identityCard: some View {
        ProjectEditorCard(title: "Identity", systemImage: "folder") {
            ProjectEditorTextField(title: "Name", text: $name, placeholder: "Project name")
            ProjectEditorTextField(title: "Prefix", text: $prefix, placeholder: "Prefix")
            ProjectEditorHelp("Items whose title starts with “\(effectivePrefix):” belong to this project.")
            ProjectEditorTextField(title: "Tagline", text: $tagline, placeholder: "Short description")
        }
    }

    private var saveLocationsCard: some View {
        ProjectEditorCard(title: "Save Locations", systemImage: "tray.and.arrow.down") {
            ProjectEditorPicker(title: "Reminders", selection: $reminderListName, options: draft.reminderLists)
            ProjectEditorPicker(title: "Calendar", selection: $calendarName, options: draft.calendars)
        }
    }

    private var integrationsCard: some View {
        ProjectEditorCard(title: "Integrations", systemImage: "curlybraces") {
            ProjectEditorTextField(title: "GitHub Repo", text: $githubRepo, placeholder: "owner/repo")
            ProjectEditorHelp("Format: owner/repo, for example anomalyco/opencode.")
        }
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

    private var projectInitial: String {
        trimmedName.first.map { String($0).uppercased() } ?? "F"
    }

    private func create() {
        let prefix = trimmedPrefix.isEmpty ? nil : trimmedPrefix
        let repo = githubRepo.trimmingCharacters(in: .whitespaces)
        onCreate(trimmedName, prefix, tagline.trimmingCharacters(in: .whitespaces),
                 reminderListName.isEmpty ? nil : reminderListName,
                 calendarName.isEmpty ? nil : calendarName,
                 repo.isEmpty ? nil : repo)
    }
}

struct EditProjectView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    let project: Project
    let onClose: () -> Void

    @State private var name = ""
    @State private var prefix = ""
    @State private var tagline = ""
    @State private var reminderListName = ""
    @State private var calendarName = ""
    @State private var githubRepo = ""
    @State private var reminderLists: [String] = []
    @State private var calendars: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            ProjectEditorHeader(title: "Edit Project",
                                subtitle: project.archived ? "Archived project" : "Project settings",
                                initial: projectInitial)
            Divider().opacity(0.7)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    identityCard
                    saveLocationsCard
                    integrationsCard
                }
                .padding(18)
            }

            Divider().opacity(0.7)
            HStack {
                if project.archived {
                    Button("Unarchive") { unarchive() }
                } else {
                    Button("Archive") { archive() }
                }
                Button("Delete", role: .destructive) { delete() }
                Spacer()
                Button("Cancel", action: onClose)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
            .controlSize(.small)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(FacetTheme.canvas)
        .frame(width: 500, height: 560)
        .onAppear(perform: loadFields)
    }

    private var identityCard: some View {
        ProjectEditorCard(title: "Identity", systemImage: "folder") {
            ProjectEditorTextField(title: "Name", text: $name, placeholder: "Project name")
            ProjectEditorTextField(title: "Prefix", text: $prefix, placeholder: "Prefix")
            ProjectEditorHelp("Items whose title starts with “\(effectivePrefix):” belong to this project.")
            if prefixWillChange {
                ProjectEditorWarning("Existing Calendar and Reminder items will keep the old “\(project.prefix):” prefix and will no longer appear here unless renamed.")
            }
            ProjectEditorTextField(title: "Tagline", text: $tagline, placeholder: "Short description")
        }
    }

    private var saveLocationsCard: some View {
        ProjectEditorCard(title: "Save Locations", systemImage: "tray.and.arrow.down") {
            ProjectEditorPicker(title: "Reminders", selection: $reminderListName, options: reminderLists)
            ProjectEditorPicker(title: "Calendar", selection: $calendarName, options: calendars)
        }
    }

    private var integrationsCard: some View {
        ProjectEditorCard(title: "Integrations", systemImage: "curlybraces") {
            ProjectEditorTextField(title: "GitHub Repo", text: $githubRepo, placeholder: "owner/repo")
            ProjectEditorHelp("Format: owner/repo, for example anomalyco/opencode.")
        }
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

    private var prefixWillChange: Bool {
        effectivePrefix != project.prefix
    }

    private var projectInitial: String {
        trimmedName.first.map { String($0).uppercased() } ?? "F"
    }

    private func loadFields() {
        reminderLists = ek.reminderListNames(enabled: settings.enabledReminderListNames)
        calendars = ek.calendarNames(enabled: settings.enabledCalendarNames)
        name = project.name
        prefix = project.prefix
        tagline = project.tagline
        githubRepo = project.githubRepo ?? ""
        reminderListName = firstAvailable(project.reminderListName,
                                          settings.defaultReminderListName,
                                          in: reminderLists)
        calendarName = firstAvailable(project.calendarName,
                                      settings.defaultCalendarName,
                                      in: calendars)
    }

    private func save() {
        var updated = project
        updated.name = trimmedName
        updated.prefix = trimmedPrefix.isEmpty ? trimmedName : trimmedPrefix
        updated.tagline = tagline.trimmingCharacters(in: .whitespaces)
        updated.reminderListName = reminderListName.isEmpty ? nil : reminderListName
        updated.calendarName = calendarName.isEmpty ? nil : calendarName
        let repo = githubRepo.trimmingCharacters(in: .whitespaces)
        updated.githubRepo = repo.isEmpty ? nil : repo
        store.update(updated)
        onClose()
    }

    private func firstAvailable(_ preferred: String?, _ fallback: String, in options: [String]) -> String {
        if let preferred, options.contains(preferred) { return preferred }
        if options.contains(fallback) { return fallback }
        return options.first ?? ""
    }

    private func archive() {
        store.archive(project)
        onClose()
    }

    private func unarchive() {
        var updated = project
        updated.archived = false
        store.update(updated)
        onClose()
    }

    private func delete() {
        store.delete(project)
        onClose()
    }
}

private struct ProjectEditorHeader: View {
    let title: String
    let subtitle: String
    let initial: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Text(initial)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct ProjectEditorCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.86))
            content
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

private struct ProjectEditorTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(FacetTheme.panel.opacity(0.70))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(FacetTheme.hairline, lineWidth: 1)
                )
        }
    }
}

private struct ProjectEditorPicker: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: $selection) {
                if options.isEmpty { Text("None").tag("") }
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 230, alignment: .trailing)
        }
    }
}

private struct ProjectEditorHelp: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

private struct ProjectEditorWarning: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.caption2)
            .foregroundStyle(.orange)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
