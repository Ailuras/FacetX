import SwiftUI

// MARK: - Shared topic appearance helpers

extension TrackPref {
    /// Resolved sidebar tint; topics default to purple (matches `topicColor`).
    var resolvedColor: Color { LabelColor.color(named: color) ?? .purple }
    /// Glyph shown in the FacetX-style badge; falls back to a tag symbol.
    var displayIcon: String { icon ?? "tag" }
}

/// FacetX-style rounded, tinted icon badge used for topics across the sidebar,
/// the editor preview, and the Rules summary list.
struct TopicBadge: View {
    let color: Color
    let icon: String
    var size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(color.opacity(0.14))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(color)
            )
    }
}

/// Drives the shared `TopicEditor` sheet from any surface: `.new` to create,
/// `.edit` to modify an existing topic.
enum TopicEditTarget: Identifiable {
    case new
    case edit(TrackPref)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let topic): return topic.id.uuidString
        }
    }

    var existing: TrackPref? {
        switch self {
        case .new: return nil
        case .edit(let topic): return topic
        }
    }
}

// MARK: - Topic editor

/// Modal editor for one topic (track): name, search query, keywords, color, and
/// sidebar glyph. Shared by the sidebar (＋ / right-click Edit) and the Rules
/// settings tab. Edits a working copy and commits to `MetadataStore` on Save.
struct TopicEditor: View {
    /// nil → create a new topic; non-nil → edit the given one.
    let existing: TrackPref?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: TrackPref
    @State private var keywordsText: String

    init(existing: TrackPref?) {
        self.existing = existing
        let base = existing ?? TrackPref(name: "", query: "", keywords: [])
        _draft = State(initialValue: base)
        _keywordsText = State(initialValue: base.keywords.joined(separator: ", "))
    }

    private var isNew: Bool { existing == nil }
    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { !trimmedName.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? L10n.pick("New Topic", "新建主题") : L10n.pick("Edit Topic", "编辑主题"))
                .font(.system(size: 15, weight: .semibold))

            preview
            Divider()
            fields
            colorPicker
            iconPicker

            Divider()
            footer
        }
        .padding(20)
        .frame(width: 440)
    }

    private var preview: some View {
        HStack(spacing: 10) {
            TopicBadge(color: draft.resolvedColor, icon: draft.displayIcon, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(trimmedName.isEmpty ? L10n.pick("Untitled", "未命名") : trimmedName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(trimmedName.isEmpty ? .secondary : .primary)
                Text(subtitlePreview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var subtitlePreview: String {
        let q = draft.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { return q }
        let kw = keywordsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return kw.isEmpty ? L10n.pick("No search query", "无搜索词") : kw.prefix(4).joined(separator: " · ")
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledField(L10n.t(.name)) {
                TextField(L10n.t(.name), text: $draft.name).textFieldStyle(.roundedBorder)
            }
            labeledField(L10n.t(.searchQuery)) {
                TextField(L10n.t(.searchQuery), text: $draft.query).textFieldStyle(.roundedBorder)
            }
            labeledField(L10n.pick("Keywords", "关键词")) {
                TextField(L10n.t(.keywordsCSV), text: $keywordsText).textFieldStyle(.roundedBorder)
            }
        }
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.75))
            content()
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.pick("Color", "颜色").uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.75))
            HStack(spacing: 8) {
                ForEach(LabelColor.allCases) { c in
                    Circle()
                        .fill(c.color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle().stroke(Color.primary.opacity(0.85), lineWidth: draft.color == c.rawValue ? 2 : 0)
                        )
                        .overlay(
                            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                        .contentShape(Circle())
                        .onTapGesture { draft.color = c.rawValue }
                }
            }
        }
    }

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.pick("Icon", "图标").uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.75))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 9), spacing: 6) {
                ForEach(SidebarGlyph.choices, id: \.symbol) { choice in
                    Button {
                        draft.icon = choice.symbol
                    } label: {
                        Image(systemName: choice.symbol)
                            .font(.system(size: 13))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(draft.icon == choice.symbol ? draft.resolvedColor : .secondary)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(draft.icon == choice.symbol ? draft.resolvedColor.opacity(0.16) : Color.secondary.opacity(0.08))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(choice.label)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(L10n.t(.cancel)) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(L10n.pick("Save", "保存")) { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
        }
    }

    private func save() {
        guard isValid else { return }
        draft.name = trimmedName
        draft.keywords = keywordsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if isNew {
            MetadataStore.shared.addTopic(draft)
        } else {
            MetadataStore.shared.updateTopic(draft)
        }
        dismiss()
    }
}
