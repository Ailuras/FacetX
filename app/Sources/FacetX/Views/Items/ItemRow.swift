import AppKit
import FacetXCore
import SwiftUI

struct InlineEditTextField: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13
    var fontWeight: NSFont.Weight = .regular
    var onCommit: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: fontSize, weight: fontWeight)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        DispatchQueue.main.async {
            textField.selectText(nil)
        }
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineEditTextField
        var didCancel = false

        init(_ parent: InlineEditTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            if didCancel { return }
            parent.onCommit()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                didCancel = true
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

struct ItemRow: View {
    @EnvironmentObject private var settings: AppSettings
    let item: ProjectItem
    let isSelected: Bool
    /// When set (cross-project views like Today), shows the owning project as a
    /// small chip next to the content. Nil inside a single project's list.
    let projectBadge: String?
    let showDragGrip: Bool
    let onDragStart: (() -> NSItemProvider)?
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void

    let inlineEditingText: Binding<String>?
    let isInlineEditing: Bool
    let onInlineCommit: (() -> Void)?
    let onInlineCancel: (() -> Void)?

    let inlineEditingNotesText: Binding<String>?
    let isInlineEditingNotes: Bool
    let onInlineNotesCommit: (() -> Void)?
    let onInlineNotesCancel: (() -> Void)?
    let onStartNotesEdit: () -> Void

    @State private var hovered = false

    init(item: ProjectItem,
         isSelected: Bool = false,
         projectBadge: String? = nil,
         showDragGrip: Bool = false,
         onDragStart: (() -> NSItemProvider)? = nil,
         onToggle: @escaping (Bool) -> Void,
         onEdit: @escaping () -> Void,
         inlineEditingText: Binding<String>? = nil,
         isInlineEditing: Bool = false,
         onInlineCommit: (() -> Void)? = nil,
         onInlineCancel: (() -> Void)? = nil,
         inlineEditingNotesText: Binding<String>? = nil,
         isInlineEditingNotes: Bool = false,
         onInlineNotesCommit: (() -> Void)? = nil,
         onInlineNotesCancel: (() -> Void)? = nil,
         onStartNotesEdit: @escaping () -> Void = {}) {
        self.item = item
        self.isSelected = isSelected
        self.projectBadge = projectBadge
        self.showDragGrip = showDragGrip
        self.onDragStart = onDragStart
        self.onToggle = onToggle
        self.onEdit = onEdit
        self.inlineEditingText = inlineEditingText
        self.isInlineEditing = isInlineEditing
        self.onInlineCommit = onInlineCommit
        self.onInlineCancel = onInlineCancel
        self.inlineEditingNotesText = inlineEditingNotesText
        self.isInlineEditingNotes = isInlineEditingNotes
        self.onInlineNotesCommit = onInlineNotesCommit
        self.onInlineNotesCancel = onInlineNotesCancel
        self.onStartNotesEdit = onStartNotesEdit
    }

    private var priorityColor: Color {
        item.priority > 0 ? FacetTheme.priorityColor(item.priority) : .clear
    }

    private var checkmarkColor: Color {
        item.isCompleted ? .green : FacetTheme.priorityColor(item.priority)
    }

    private var borderHighlightColor: Color {
        item.rowTint
    }

    private var rowFill: Color {
        if isSelected { return FacetTheme.softAccent }
        if hovered { return Color.primary.opacity(0.035) }
        return FacetTheme.quietPanel
    }

    private var rowStroke: Color {
        if isSelected { return Color.accentColor.opacity(0.72) }
        if hovered { return borderHighlightColor.opacity(0.32) }
        return FacetTheme.hairline
    }

    private var dragGripDots: some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 2) {
                    Circle().fill(Color.secondary.opacity(hovered ? 0.6 : 0.3))
                        .frame(width: 3, height: 3)
                    Circle().fill(Color.secondary.opacity(hovered ? 0.6 : 0.3))
                        .frame(width: 3, height: 3)
                }
            }
        }
        .frame(width: 8)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .center, spacing: 10) {
                    if showDragGrip {
                        if let onDragStart = onDragStart {
                            dragGripDots
                                .frame(width: 16, height: 28)
                                .contentShape(Rectangle())
                                .hoverCursor(.openHand)
                                .onDrag {
                                    onDragStart()
                                } preview: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "line.3.horizontal")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(item.content)
                                            .font(.system(size: 12, weight: .medium))
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(FacetTheme.quietPanel)
                                    .foregroundColor(.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)
                                }
                        } else {
                            dragGripDots
                                .frame(width: 16, height: 28)
                                .contentShape(Rectangle())
                        }
                    }

                    if item.facetKind == .task {
                        Button { onToggle(!item.isCompleted) } label: {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(checkmarkColor)
                        }
                        .buttonStyle(.plain)
                        .help(item.isCompleted ? L10n.pick("Mark incomplete", "标记为未完成")
                                               : L10n.pick("Mark complete", "标记为完成"))
                    } else {
                        Image(systemName: item.facetKind.systemImage)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(item.facetKind.color)
                    }

                    if isInlineEditing, let inlineEditingText {
                        InlineEditTextField(text: inlineEditingText,
                                            fontSize: 14,
                                            fontWeight: .semibold,
                                            onCommit: { onInlineCommit?() },
                                            onCancel: { onInlineCancel?() })
                            .frame(minHeight: 22)
                    } else {
                        HStack(spacing: 6) {
                            Text(item.content)
                                .font(.system(size: 13, weight: .medium))
                                .strikethrough(item.isCompleted)
                                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                .lineLimit(1)

                            if let projectBadge {
                                Text(projectBadge)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.12))
                                    .clipShape(Capsule())
                            }



                            if !item.linkedCommits.isEmpty {
                                Image(systemName: "source.branch")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.purple)
                                    .help(L10n.pick("Linked Commits", "已关联提交"))
                            }

                            ForEach(item.tags, id: \.self) { tag in
                                let tagColor = settings.tagColor(for: tag)
                                HStack(spacing: 2) {
                                    Text("#")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(tagColor.opacity(0.65))
                                    Text(tag)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(tagColor)
                                        .lineLimit(1)
                                }
                                .fixedSize()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(tagColor.opacity(0.12))
                                )
                            }
                        }
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        if !isInlineEditing, let url = item.url {
                            Link(destination: url) {
                                FacetInfoBadge(
                                    text: url.host?.replacingOccurrences(of: "www.", with: "") ?? "Link",
                                    systemImage: "link",
                                    tint: .blue,
                                    fill: Color.blue.opacity(0.10)
                                )
                            }
                            .buttonStyle(.plain)
                            .help(L10n.pick("Open link: \(url.absoluteString)", "打开链接：\(url.absoluteString)"))
                        }

                        if let date = item.date {
                            FacetInfoBadge(
                                text: formattedDate(date),
                                systemImage: item.kind == .reminder ? "calendar.badge.clock" : "clock",
                                tint: dateHighlightColor(for: date),
                                fill: dateHighlightColor(for: date).opacity(0.10)
                            )
                        }

                        if !isInlineEditing {
                            Button {
                                onEdit()
                            } label: {
                                Image(systemName: "pencil")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .opacity(hovered ? 1.0 : 0.0)
                            .help(L10n.pick("Edit item", "编辑条目"))
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                        .fill(rowFill)
                    if item.kind == .reminder && item.priority > 0 {
                        RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                            .fill(priorityColor.opacity(0.025))
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                    .stroke(rowStroke, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .onHover { isHovered in
            withAnimation(.easeOut(duration: 0.15)) {
                hovered = isHovered
            }
        }
    }

    private func dateHighlightColor(for date: Date) -> Color {
        if item.isCompleted { return .secondary }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return .orange
        } else if date < Date() {
            return .red
        }
        return .secondary
    }

    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let hasTime = item.kind == .event ? !item.isAllDay : item.hasTime

        if calendar.isDateInToday(date) {
            if hasTime {
                return "\(L10n.pick("Today", "今天")) \(timeString(date))"
            } else {
                return L10n.pick("Today", "今天")
            }
        } else if calendar.isDateInTomorrow(date) {
            if hasTime {
                return "\(L10n.pick("Tomorrow", "明天")) \(timeString(date))"
            } else {
                return L10n.pick("Tomorrow", "明天")
            }
        } else if calendar.isDateInYesterday(date) {
            return L10n.pick("Yesterday", "昨天")
        } else {
            if hasTime {
                return "\(shortDateString(date, calendar: calendar)) \(timeString(date))"
            } else {
                return shortDateString(date, calendar: calendar)
            }
        }
    }

    private func shortDateString(_ date: Date, calendar: Calendar) -> String {
        if L10n.language == "zh" {
            let month = calendar.component(.month, from: date)
            let day = calendar.component(.day, from: date)
            return "\(month)月\(day)日"
        }

        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

/// All-view drop target: the handler receives the dragged and target items
/// on enter to update an optimistic preview (same-kind reorder OR cross-kind
/// kind-swap), and onDrop to commit whatever the preview ended up as.
struct ItemDropDelegate: DropDelegate {
    let item: ProjectItem
    @Binding var draggedItem: ProjectItem?
    var onEntered: (ProjectItem, ProjectItem) -> Void
    var onDrop: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard draggedItem != nil else { return false }
        onDrop()
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem, draggedItem.id != item.id else { return }
        onEntered(draggedItem, item)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}
