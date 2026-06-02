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
        VStack(alignment: .leading, spacing: 16) {
            Text("New Project").font(.title2).bold()

            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                    TextField("Prefix", text: $prefix)
                    Text("Items whose title starts with “\(effectivePrefix):” belong to this project.")
                        .font(.caption2).foregroundStyle(.secondary)
                    TextField("Tagline", text: $tagline)
                    Picker("Reminders", selection: $reminderListName) {
                        if draft.reminderLists.isEmpty { Text("None").tag("") }
                        ForEach(draft.reminderLists, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Calendar", selection: $calendarName) {
                        if draft.calendars.isEmpty { Text("None").tag("") }
                        ForEach(draft.calendars, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("GitHub repo (optional)", text: $githubRepo)
                        .textFieldStyle(.roundedBorder)
                    Text("Format: owner/repo  —  e.g. anomalyco/opencode")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || reminderListName.isEmpty || calendarName.isEmpty)
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Project").font(.title2).bold()

            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                    TextField("Prefix", text: $prefix)
                    Text("Items whose title starts with “\(effectivePrefix):” belong to this project.")
                        .font(.caption2).foregroundStyle(.secondary)
                    if prefixWillChange {
                        Label("Existing Calendar and Reminder items will keep the old “\(project.prefix):” prefix and will no longer appear here unless renamed.", systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    TextField("Tagline", text: $tagline)
                    Picker("Reminders", selection: $reminderListName) {
                        if reminderLists.isEmpty { Text("None").tag("") }
                        ForEach(reminderLists, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Calendar", selection: $calendarName) {
                        if calendars.isEmpty { Text("None").tag("") }
                        ForEach(calendars, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("GitHub repo (optional)", text: $githubRepo)
                        .textFieldStyle(.roundedBorder)
                    Text("Format: owner/repo  —  e.g. anomalyco/opencode")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

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
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear(perform: loadFields)
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
