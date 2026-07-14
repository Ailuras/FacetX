import SwiftUI

struct TopicEditorSheet: View {
    let onSave: (TrackPref) -> Void
    let onCancel: () -> Void

    private let existingID: UUID?

    @State private var name = ""
    @State private var query = ""
    @State private var keywordsText = ""
    @State private var colorName = "purple"
    @State private var iconName = "books.vertical"

    init(onSave: @escaping (TrackPref) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        self.existingID = nil
    }

    init(topic: TrackPref, onSave: @escaping (TrackPref) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        self.existingID = topic.id
        _name = State(initialValue: topic.name)
        _query = State(initialValue: topic.query)
        _keywordsText = State(initialValue: topic.keywords.joined(separator: ", "))
        _colorName = State(initialValue: topic.color ?? "purple")
        _iconName = State(initialValue: topic.icon ?? "books.vertical")
    }

    private var tint: Color { LabelColor.color(named: colorName) ?? .purple }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var topicInitial: String { trimmedName.first.map { String($0).uppercased() } ?? "L" }

    var body: some View {
        VStack(spacing: 0) {
            WorkEditorHeader(
                title: existingID == nil ? L10n.pick("New Library", "新建文献库") : L10n.pick("Edit Library", "编辑文献库"),
                subtitle: L10n.pick("Literature library settings", "文献库设置"),
                initial: topicInitial,
                tint: tint,
                systemImage: iconName
            )
            Divider().opacity(0.7)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    identityCard
                    fetchCard
                    appearanceCard
                }
                .padding(18)
            }

            Divider().opacity(0.7)
            HStack {
                Spacer()
                Button(L10n.t(.cancel), action: onCancel)
                Button(L10n.t(.save)) { save() }
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
    }

    private var identityCard: some View {
        WorkEditorCard(title: L10n.pick("Identity", "基本信息"), systemImage: "books.vertical") {
            WorkEditorTextField(title: L10n.pick("Name", "名称"), text: $name,
                                   placeholder: L10n.pick("Library name", "文献库名称"))
            WorkEditorHelp(L10n.pick("Papers in this library are grouped under this name.",
                                        "该文献库下的文献以此名称归类。"))
        }
    }

    private var fetchCard: some View {
        WorkEditorCard(title: L10n.pick("Fetching", "拉取"), systemImage: "magnifyingglass") {
            WorkEditorTextField(title: L10n.pick("Search Query", "检索式"), text: $query,
                                   placeholder: L10n.pick("OpenAlex search terms", "OpenAlex 检索词"))
            WorkEditorHelp(L10n.pick("Used by Fetch to pull recent papers from OpenAlex.",
                                        "“拉取”按钮据此从 OpenAlex 获取近期文献。"))
            WorkEditorTextField(title: L10n.pick("Keywords", "关键词"), text: $keywordsText,
                                   placeholder: L10n.pick("comma, separated, keywords", "逗号, 分隔, 关键词"))
            WorkEditorHelp(L10n.pick("Fetched papers must match at least one keyword.",
                                        "拉取的文献需至少匹配一个关键词。"))
        }
    }

    private var appearanceCard: some View {
        WorkEditorCard(title: L10n.pick("Appearance", "外观"), systemImage: "paintpalette") {
            VStack(alignment: .leading, spacing: 12) {
                colorRow
                iconGrid
            }
        }
    }

    private var colorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.pick("Color", "颜色"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(LabelColor.allCases, id: \.self) { option in
                    Button {
                        colorName = option.rawValue
                    } label: {
                        ZStack {
                            Circle().fill(option.color)
                            if colorName == option.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().stroke(Color.primary.opacity(colorName == option.rawValue ? 0.18 : 0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var iconGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.pick("Icon", "图标"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 7), count: 8),
                      alignment: .leading, spacing: 7) {
                ForEach(SidebarGlyph.choices, id: \.symbol) { choice in
                    Button {
                        iconName = choice.symbol
                    } label: {
                        Image(systemName: choice.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(iconName == choice.symbol ? tint : .secondary)
                            .frame(width: 30, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(iconName == choice.symbol ? tint.opacity(0.14) : FacetTheme.panel.opacity(0.58))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(iconName == choice.symbol ? tint.opacity(0.34) : FacetTheme.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func save() {
        let keywords = keywordsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let topic = TrackPref(
            id: existingID ?? UUID(),
            name: trimmedName,
            query: query.trimmingCharacters(in: .whitespacesAndNewlines),
            keywords: keywords,
            color: colorName,
            icon: iconName
        )
        onSave(topic)
    }
}
