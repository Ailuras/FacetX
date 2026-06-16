import SwiftUI

struct TopicEditorSheet: View {
    let onSave: (TrackPref) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var query = ""
    @State private var keywordsText = ""
    @State private var selectedColor: String? = nil
    @State private var selectedIcon = "tag"

    init(onSave: @escaping (TrackPref) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
    }

    init(topic: TrackPref, onSave: @escaping (TrackPref) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: topic.name)
        _query = State(initialValue: topic.query)
        _keywordsText = State(initialValue: topic.keywords.joined(separator: ", "))
        _selectedColor = State(initialValue: topic.color)
        _selectedIcon = State(initialValue: topic.icon ?? "tag")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
                .padding(20)
        }
        .frame(width: 380)
    }

    private var header: some View {
        HStack {
            Text("Topic").font(.headline)
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                let keywords = keywordsText
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                let topic = TrackPref(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                    keywords: keywords,
                    color: selectedColor,
                    icon: selectedIcon
                )
                onSave(topic)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextField("Topic name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Search Query").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextField("OpenAlex search query", text: $query)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Keywords (comma-separated)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextField("keyword1, keyword2", text: $keywordsText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 20) {
                colorPicker
                iconPicker
            }
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Color").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: .init(.fixed(24)), count: 6), spacing: 6) {
                ForEach(LabelColor.allCases, id: \.self) { labelColor in
                    Button {
                        selectedColor = labelColor.rawValue
                    } label: {
                        Circle()
                            .fill(labelColor.color)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                            )
                            .overlay(alignment: .center) {
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Icon").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: .init(.fixed(24)), count: 6), spacing: 6) {
                ForEach(SidebarGlyph.choices, id: \.symbol) { choice in
                    Button {
                        selectedIcon = choice.symbol
                    } label: {
                        Image(systemName: choice.symbol)
                            .font(.system(size: 13))
                            .frame(width: 18, height: 18)
                            .padding(2)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(selectedIcon == choice.symbol
                                          ? Color.accentColor.opacity(0.12)
                                          : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(selectedIcon == choice.symbol
                                            ? Color.accentColor.opacity(0.5)
                                            : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
