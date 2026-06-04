import SwiftUI

struct EditProjectView: View {
    @EnvironmentObject private var ek: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var toast: ToastController

    let project: Project
    let onClose: () -> Void

    @State private var name = ""
    @State private var prefix = ""
    @State private var tagline = ""
    @State private var reminderListName = ""
    @State private var calendarName = ""
    @State private var weekGoalCalendarName = ""
    @State private var githubRepo = ""
    @State private var colorName = ProjectAppearance.defaultColorName
    @State private var iconName = ProjectAppearance.defaultIconName
    @State private var reminderLists: [String] = []
    @State private var calendars: [String] = []
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            ProjectEditorHeader(title: "Edit Project",
                                subtitle: project.archived ? "Archived project" : "Project settings",
                                initial: projectInitial,
                                tint: ProjectAppearance.color(for: colorName),
                                systemImage: ProjectAppearance.iconName(for: iconName))
            Divider().opacity(0.7)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    identityCard
                    appearanceCard
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
                Button("Delete", role: .destructive) { confirmDelete = true }
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
        .frame(width: 500, height: 650)
        .onAppear(perform: loadFields)
        .alert("Delete project?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                delete()
            }
        } message: {
            Text("“\(project.name)” will be removed. Its items remain in Calendar/Reminders.")
        }
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

    private var appearanceCard: some View {
        ProjectEditorCard(title: "Appearance", systemImage: "paintpalette") {
            ProjectEditorAppearancePicker(colorName: $colorName, iconName: $iconName, initial: projectInitial)
        }
    }

    private var saveLocationsCard: some View {
        ProjectEditorCard(title: "Save Locations", systemImage: "tray.and.arrow.down") {
            ProjectEditorPicker(title: "Reminders", selection: $reminderListName, options: reminderLists)
            ProjectEditorPicker(title: "Calendar", selection: $calendarName, options: calendars)
            ProjectEditorPicker(title: "Goal Calendar", selection: $weekGoalCalendarName, options: calendars)
        }
    }

    private var integrationsCard: some View {
        ProjectEditorCard(title: "Integrations", systemImage: "curlybraces") {
            ProjectEditorGitHubRepoPicker(selection: $githubRepo)
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
        reminderLists = ek.reminderListNames(enabled: settings.effectiveReminderListNames)
        calendars = ek.calendarNames(enabled: settings.effectiveCalendarNames)
        name = project.name
        prefix = project.prefix
        tagline = project.tagline
        githubRepo = project.githubRepo ?? ""
        colorName = project.colorName ?? ProjectAppearance.defaultColorName
        iconName = project.iconName ?? ProjectAppearance.defaultIconName
        reminderListName = firstAvailable(project.reminderListName,
                                          settings.defaultReminderListName,
                                          in: reminderLists)
        calendarName = firstAvailable(project.calendarName,
                                      settings.defaultCalendarName,
                                      in: calendars)
        weekGoalCalendarName = firstAvailable(project.weekGoalCalendarName,
                                             settings.weekGoalCalendarName,
                                             in: calendars)
    }

    private func save() {
        var updated = project
        updated.name = trimmedName
        updated.prefix = trimmedPrefix.isEmpty ? trimmedName : trimmedPrefix
        updated.tagline = tagline.trimmingCharacters(in: .whitespaces)
        updated.reminderListName = reminderListName.isEmpty ? nil : reminderListName
        updated.calendarName = calendarName.isEmpty ? nil : calendarName
        updated.weekGoalCalendarName = weekGoalCalendarName.isEmpty ? nil : weekGoalCalendarName
        updated.colorName = colorName
        updated.iconName = iconName
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
        toast.show("Project archived", type: .info)
        onClose()
    }

    private func unarchive() {
        var updated = project
        updated.archived = false
        store.update(updated)
        toast.show("Project unarchived", type: .success)
        onClose()
    }

    private func delete() {
        store.delete(project)
        toast.show("Project deleted", type: .success)
        onClose()
    }
}
