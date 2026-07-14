import SwiftUI

struct NewWorkView: View {
    let draft: WorkDraft
    let onCreate: (String, String?, String, String?, String?, String?, String, String, String?, String?) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var prefix: String
    @State private var tagline: String
    @State private var reminderListName: String
    @State private var calendarName: String
    @State private var weekGoalCalendarName: String
    @State private var githubRepo: String
    @State private var githubLocalPath: String
    @State private var colorName: String
    @State private var iconName: String

    init(draft: WorkDraft,
         onCreate: @escaping (String, String?, String, String?, String?, String?, String, String, String?, String?) -> Void,
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
        _githubLocalPath = State(initialValue: draft.githubLocalPath)
        _colorName = State(initialValue: draft.colorName)
        _iconName = State(initialValue: draft.iconName)
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkEditorHeader(title: L10n.pick("New Work", "新建项目"),
                                subtitle: L10n.pick("Create a facet over Calendar and Reminders",
                                                    "为日历与提醒事项创建一个分面"),
                                initial: workInitial,
                                tint: WorkAppearance.color(for: colorName),
                                systemImage: WorkAppearance.iconName(for: iconName))
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
                    .disabled(trimmedName.isEmpty || !hasSaveLocations)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(FacetTheme.canvas)
        .frame(width: 500, height: 650)
    }

    private var identityCard: some View {
        WorkEditorCard(title: L10n.pick("Identity", "标识"), systemImage: "folder") {
            WorkEditorTextField(title: L10n.pick("Name", "名称"), text: $name, placeholder: L10n.pick("Work name", "项目名称"))
            WorkEditorTextField(title: L10n.pick("Prefix", "前缀"), text: $prefix, placeholder: L10n.pick("Prefix", "前缀"))
            WorkEditorHelp(L10n.pick("Items whose title starts with “\(effectivePrefix):” belong to this work.",
                                        "标题以“\(effectivePrefix):”开头的条目属于该项目。"))
            WorkEditorTextField(title: L10n.pick("Tagline", "标语"), text: $tagline, placeholder: L10n.pick("Short description", "简短描述"))
        }
    }

    private var appearanceCard: some View {
        WorkEditorCard(title: L10n.pick("Appearance", "外观"), systemImage: "paintpalette") {
            WorkEditorAppearancePicker(colorName: $colorName, iconName: $iconName, initial: workInitial)
        }
    }

    private var saveLocationsCard: some View {
        WorkEditorCard(title: L10n.pick("Save Locations", "保存位置"), systemImage: "tray.and.arrow.down") {
            WorkEditorPicker(title: L10n.pick("Reminders", "提醒事项"), selection: $reminderListName, options: draft.reminderLists)
            WorkEditorPicker(title: L10n.pick("Calendar", "日历"), selection: $calendarName, options: draft.calendars)
            WorkEditorPicker(title: L10n.pick("Goal Calendar", "目标日历"), selection: $weekGoalCalendarName, options: draft.calendars)
        }
    }

    private var integrationsCard: some View {
        WorkEditorCard(title: L10n.pick("Integrations", "集成"), systemImage: "curlybraces") {
            WorkEditorGitHubRepoPicker(selection: $githubRepo, localPath: $githubLocalPath)
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

    private var workInitial: String {
        trimmedName.first.map { String($0).uppercased() } ?? "F"
    }

    private var hasSaveLocations: Bool {
        !reminderListName.isEmpty
            && !calendarName.isEmpty
    }

    private func create() {
        let prefix = trimmedPrefix.isEmpty ? nil : trimmedPrefix
        let repo = githubRepo.trimmingCharacters(in: .whitespaces)
        let repoPath = githubLocalPath.trimmingCharacters(in: .whitespaces)
        onCreate(trimmedName, prefix, tagline.trimmingCharacters(in: .whitespaces),
                 reminderListName.isEmpty ? nil : reminderListName,
                 calendarName.isEmpty ? nil : calendarName,
                 weekGoalCalendarName.isEmpty ? nil : weekGoalCalendarName,
                 colorName,
                 iconName,
                 repo.isEmpty ? nil : repo,
                 repoPath.isEmpty ? nil : repoPath)
    }
}
