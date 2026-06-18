import SwiftUI

struct NewProjectView: View {
    let draft: ProjectDraft
    let onCreate: (String, String?, String, String?, String?, String?, String?, String, String, String?) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var prefix: String
    @State private var tagline: String
    @State private var reminderListName: String
    @State private var calendarName: String
    @State private var weekGoalCalendarName: String
    @State private var literatureCalendarName: String
    @State private var githubRepo: String
    @State private var colorName: String
    @State private var iconName: String

    init(draft: ProjectDraft,
         onCreate: @escaping (String, String?, String, String?, String?, String?, String?, String, String, String?) -> Void,
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
        _literatureCalendarName = State(initialValue: draft.literatureCalendarName)
        _githubRepo = State(initialValue: draft.githubRepo)
        _colorName = State(initialValue: draft.colorName)
        _iconName = State(initialValue: draft.iconName)
    }

    var body: some View {
        VStack(spacing: 0) {
            ProjectEditorHeader(title: L10n.pick("New Project", "新建项目"),
                                subtitle: L10n.pick("Create a facet over Calendar and Reminders",
                                                    "为日历与提醒事项创建一个分面"),
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
                Button(L10n.pick("Cancel", "取消"), action: onCancel)
                    .controlSize(.small)
                Button(L10n.pick("Create", "创建")) { create() }
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
        ProjectEditorCard(title: L10n.pick("Identity", "标识"), systemImage: "folder") {
            ProjectEditorTextField(title: L10n.pick("Name", "名称"), text: $name, placeholder: L10n.pick("Project name", "项目名称"))
            ProjectEditorTextField(title: L10n.pick("Prefix", "前缀"), text: $prefix, placeholder: L10n.pick("Prefix", "前缀"))
            ProjectEditorHelp(L10n.pick("Items whose title starts with “\(effectivePrefix):” belong to this project.",
                                        "标题以“\(effectivePrefix):”开头的条目属于该项目。"))
            ProjectEditorTextField(title: L10n.pick("Tagline", "标语"), text: $tagline, placeholder: L10n.pick("Short description", "简短描述"))
        }
    }

    private var appearanceCard: some View {
        ProjectEditorCard(title: L10n.pick("Appearance", "外观"), systemImage: "paintpalette") {
            ProjectEditorAppearancePicker(colorName: $colorName, iconName: $iconName, initial: projectInitial)
        }
    }

    private var saveLocationsCard: some View {
        ProjectEditorCard(title: L10n.pick("Save Locations", "保存位置"), systemImage: "tray.and.arrow.down") {
            ProjectEditorPicker(title: L10n.pick("Reminders", "提醒事项"), selection: $reminderListName, options: draft.reminderLists)
            ProjectEditorPicker(title: L10n.pick("Calendar", "日历"), selection: $calendarName, options: draft.calendars)
            ProjectEditorPicker(title: L10n.pick("Goal Calendar", "目标日历"), selection: $weekGoalCalendarName, options: draft.calendars)
            ProjectEditorPicker(title: L10n.pick("Literature Calendar", "文献日历"), selection: $literatureCalendarName, options: draft.calendars)
            if calendarName == literatureCalendarName && !calendarName.isEmpty {
                ProjectEditorWarning(L10n.pick("Calendar and Literature Calendar should not be the same.",
                                               "条目日历与文献日历不应相同。"))
            }
        }
    }

    private var integrationsCard: some View {
        ProjectEditorCard(title: L10n.pick("Integrations", "集成"), systemImage: "curlybraces") {
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
                 literatureCalendarName.isEmpty ? nil : literatureCalendarName,
                 colorName,
                 iconName,
                 repo.isEmpty ? nil : repo)
    }
}
