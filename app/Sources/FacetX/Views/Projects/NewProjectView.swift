import SwiftUI

struct NewProjectView: View {
    let draft: ProjectDraft
    let onCreate: (String, String?, String, String?, String?, String?, String, String, String?) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var prefix: String
    @State private var tagline: String
    @State private var reminderListName: String
    @State private var calendarName: String
    @State private var weekGoalCalendarName: String
    @State private var githubRepo: String
    @State private var colorName: String
    @State private var iconName: String

    init(draft: ProjectDraft,
         onCreate: @escaping (String, String?, String, String?, String?, String?, String, String, String?) -> Void,
         onCancel: @escaping () -> Void) {
        self.draft = draft
        self.onCreate = onCreate
        self.onCancel = onCancel
        _name = State(initialValue: draft.name)
        _prefix = State(initialValue: draft.prefix)
        _tagline = State(initialValue: draft.tagline)
        _reminderListName = State(initialValue: draft.reminderListName)
        _calendarName = State(initialValue: draft.calendarName)
        _weekGoalCalendarName = State(initialValue: draft.weekGoalCalendarName)
        _githubRepo = State(initialValue: draft.githubRepo)
        _colorName = State(initialValue: draft.colorName)
        _iconName = State(initialValue: draft.iconName)
    }

    var body: some View {
        VStack(spacing: 0) {
            ProjectEditorHeader(title: "New Project",
                                subtitle: "Create a facet over Calendar and Reminders",
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
        .frame(width: 500, height: 650)
    }

    private var identityCard: some View {
        ProjectEditorCard(title: "Identity", systemImage: "folder") {
            ProjectEditorTextField(title: "Name", text: $name, placeholder: "Project name")
            ProjectEditorTextField(title: "Prefix", text: $prefix, placeholder: "Prefix")
            ProjectEditorHelp("Items whose title starts with “\(effectivePrefix):” belong to this project.")
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
            ProjectEditorPicker(title: "Reminders", selection: $reminderListName, options: draft.reminderLists)
            ProjectEditorPicker(title: "Calendar", selection: $calendarName, options: draft.calendars)
            ProjectEditorPicker(title: "Goal Calendar", selection: $weekGoalCalendarName, options: draft.calendars)
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

    private var projectInitial: String {
        trimmedName.first.map { String($0).uppercased() } ?? "F"
    }

    private func create() {
        let prefix = trimmedPrefix.isEmpty ? nil : trimmedPrefix
        let repo = githubRepo.trimmingCharacters(in: .whitespaces)
        onCreate(trimmedName, prefix, tagline.trimmingCharacters(in: .whitespaces),
                 reminderListName.isEmpty ? nil : reminderListName,
                 calendarName.isEmpty ? nil : calendarName,
                 weekGoalCalendarName.isEmpty ? nil : weekGoalCalendarName,
                 colorName,
                 iconName,
                 repo.isEmpty ? nil : repo)
    }
}
