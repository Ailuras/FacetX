import SwiftUI

struct TopicEditorSheet: View {
    let onSave: (TrackPref) -> Void
    let onCancel: () -> Void

    private let existingID: UUID?

    @State private var name = ""
    @State private var query = ""
    @State private var keywordsText = ""
    @State private var selectedColor: String? = "purple"
    @State private var selectedIcon = "books.vertical"

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
        _selectedColor = State(initialValue: topic.color)
        _selectedIcon = State(initialValue: topic.icon ?? "books.vertical")
    }

    private var tint: Color { LabelColor.color(named: selectedColor) ?? .purple }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                form.padding(20)
            }
        }
        .frame(width: 420, height: 540)
    }

    private var header: some View {
        HStack {
            Text(existingID == nil ? L10n.pick("New Library", "新建文献库") : L10n.pick("Edit Library", "编辑文献库"))
                .font(.headline)
            Spacer()
            Button(L10n.t(.cancel), action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(L10n.t(.save)) { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(trimmedName.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            preview

            field(L10n.pick("Name", "名称"), required: true) {
                TextField(L10n.pick("e.g. SAT Solving", "例如：SAT 求解"), text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            field(L10n.pick("Search Query", "检索式")) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField(L10n.pick("OpenAlex search terms", "OpenAlex 检索词"), text: $query)
                        .textFieldStyle(.roundedBorder)
                    Text(L10n.pick("Used by Fetch to pull recent papers from OpenAlex.",
                                   "“拉取”按钮据此从 OpenAlex 获取近期文献。"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            field(L10n.pick("Keywords", "关键词")) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField(L10n.pick("comma, separated, keywords", "逗号, 分隔, 关键词"), text: $keywordsText)
                        .textFieldStyle(.roundedBorder)
                    Text(L10n.pick("Fetched papers must match at least one keyword.",
                                   "拉取的文献需至少匹配一个关键词。"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            colorPicker
            iconPicker
        }
    }

    private var preview: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.14))
                Image(systemName: selectedIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(trimmedName.isEmpty ? L10n.pick("New Library", "新建文献库") : trimmedName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(trimmedName.isEmpty ? .secondary : .primary)
                Text(L10n.pick("0 papers", "0 篇文献"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func field<Content: View>(_ label: String, required: Bool = false,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 3) {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if required { Text("*").font(.caption.weight(.bold)).foregroundStyle(.red) }
            }
            content()
        }
    }

    private var colorPicker: some View {
        field(L10n.pick("Color", "颜色")) {
            LazyVGrid(columns: Array(repeating: .init(.fixed(26)), count: 8), spacing: 8) {
                ForEach(LabelColor.allCases, id: \.self) { labelColor in
                    Button {
                        selectedColor = labelColor.rawValue
                    } label: {
                        Circle()
                            .fill(labelColor.color)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                            .overlay {
                                if selectedColor == labelColor.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var iconPicker: some View {
        field(L10n.pick("Icon", "图标")) {
            LazyVGrid(columns: Array(repeating: .init(.fixed(30)), count: 8), spacing: 8) {
                ForEach(SidebarGlyph.choices, id: \.symbol) { choice in
                    Button {
                        selectedIcon = choice.symbol
                    } label: {
                        Image(systemName: choice.symbol)
                            .font(.system(size: 14))
                            .foregroundStyle(selectedIcon == choice.symbol ? tint : .primary)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedIcon == choice.symbol ? tint.opacity(0.14) : Color.secondary.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selectedIcon == choice.symbol ? tint.opacity(0.5) : Color.clear, lineWidth: 1)
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
            color: selectedColor,
            icon: selectedIcon
        )
        onSave(topic)
    }
}
