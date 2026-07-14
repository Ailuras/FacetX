import AppKit
import SwiftUI

struct GitDiffView: View {
    let text: String
    let isLoading: Bool

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    L10n.pick("No Diff", "暂无差异"),
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(L10n.pick("Select a change or commit to inspect it.",
                                                "选择一个变更或提交以检查差异。"))
                )
            } else {
                GitDiffTextView(text: text)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.52))
    }
}

/// A single AppKit text layout replaces thousands of SwiftUI row views. Large
/// commits remain scrollable and selectable without blocking the main window.
private struct GitDiffTextView: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.72)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true

        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(
            containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        )
        container.widthTracksTextView = false
        layoutManager.addTextContainer(container)

        let textView = NSTextView(frame: .zero, textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.usesFindPanel = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.setAccessibilityLabel(L10n.pick("Git diff", "Git 差异"))

        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.render(text, in: textView)
    }

    @MainActor
    final class Coordinator {
        var renderedText: String?
        var renderTask: Task<Void, Never>?

        func render(_ text: String, in textView: NSTextView) {
            guard renderedText != text else { return }
            renderedText = text
            renderTask?.cancel()

            textView.string = L10n.pick("Rendering diff…", "正在渲染差异…")
            let work = Task.detached(priority: .userInitiated) {
                SendableAttributedString(value: GitDiffTextView.render(text))
            }
            renderTask = Task { [weak self, weak textView] in
                let rendered = await work.value
                guard !Task.isCancelled,
                      self?.renderedText == text,
                      let textView,
                      let storage = textView.textStorage else { return }
                storage.setAttributedString(rendered.value)
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
            }
        }

        deinit { renderTask?.cancel() }
    }

    private struct SendableAttributedString: @unchecked Sendable {
        let value: NSAttributedString
    }

    private enum LineKind {
        case addition
        case deletion
        case hunk
        case header
        case context
        case notice
    }

    private struct StyleSpan {
        let range: NSRange
        let kind: LineKind
    }

    nonisolated private static let maximumCharacters = 4_000_000
    nonisolated private static let maximumLines = 20_000

    nonisolated private static func render(_ raw: String) -> NSAttributedString {
        let characterLimited = raw.count > maximumCharacters
        let visible = characterLimited ? String(raw.prefix(maximumCharacters)) : raw
        let allLines = visible.components(separatedBy: .newlines)
        let lineLimited = allLines.count > maximumLines
        let lines = allLines.prefix(maximumLines)

        var output = ""
        output.reserveCapacity(min(visible.utf8.count + lines.count * 18, maximumCharacters + maximumLines * 18))
        var spans: [StyleSpan] = []
        spans.reserveCapacity(lines.count + 1)
        var numberRanges: [NSRange] = []
        numberRanges.reserveCapacity(lines.count + 1)
        var utf16Offset = 0
        var oldLine: Int?
        var newLine: Int?

        for line in lines {
            let parsed = parse(line, oldLine: &oldLine, newLine: &newLine)
            let prefix = "\(padded(parsed.oldLine)) \(padded(parsed.newLine)) │ "
            let renderedLine = prefix + line + "\n"
            let prefixLength = prefix.utf16.count
            let lineLength = renderedLine.utf16.count
            numberRanges.append(NSRange(location: utf16Offset, length: prefixLength))
            spans.append(StyleSpan(range: NSRange(location: utf16Offset + prefixLength,
                                                  length: lineLength - prefixLength),
                                   kind: parsed.kind))
            output += renderedLine
            utf16Offset += lineLength
        }

        if characterLimited || lineLimited {
            let notice = L10n.pick(
                "Diff preview truncated to keep the editor responsive. Open the repository for the complete diff.",
                "差异预览已截断以保持编辑器流畅；请在仓库中查看完整差异。"
            )
            let prefix = "       " + "       │ "
            let renderedLine = prefix + notice + "\n"
            let prefixLength = prefix.utf16.count
            let lineLength = renderedLine.utf16.count
            numberRanges.append(NSRange(location: utf16Offset, length: prefixLength))
            spans.append(StyleSpan(range: NSRange(location: utf16Offset + prefixLength,
                                                  length: lineLength - prefixLength),
                                   kind: .notice))
            output += renderedLine
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 18
        paragraph.maximumLineHeight = 18
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let attributed = NSMutableAttributedString(string: output, attributes: base)
        for range in numberRanges {
            attributed.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
        }
        for span in spans {
            attributed.addAttributes(attributes(for: span.kind), range: span.range)
        }
        return attributed
    }

    nonisolated private static func parse(_ text: String,
                              oldLine: inout Int?,
                              newLine: inout Int?) -> (oldLine: Int?, newLine: Int?, kind: LineKind) {
        if text.hasPrefix("@@") {
            let ranges = hunkRanges(text)
            oldLine = ranges.old
            newLine = ranges.new
            return (nil, nil, .hunk)
        }
        if text.hasPrefix("diff --git") || text.hasPrefix("index ")
            || text.hasPrefix("--- ") || text.hasPrefix("+++ ")
            || text.hasPrefix("new file") || text.hasPrefix("deleted file")
            || text.hasPrefix("similarity index") || text.hasPrefix("rename ") {
            return (nil, nil, .header)
        }
        if text.hasPrefix("+") {
            let current = newLine
            newLine = newLine.map { $0 + 1 }
            return (nil, current, .addition)
        }
        if text.hasPrefix("-") {
            let current = oldLine
            oldLine = oldLine.map { $0 + 1 }
            return (current, nil, .deletion)
        }
        let currentOld = oldLine
        let currentNew = newLine
        oldLine = oldLine.map { $0 + 1 }
        newLine = newLine.map { $0 + 1 }
        return (currentOld, currentNew, .context)
    }

    nonisolated private static func padded(_ value: Int?) -> String {
        let text = value.map(String.init) ?? ""
        return String(repeating: " ", count: max(0, 6 - text.count)) + text
    }

    nonisolated private static func attributes(for kind: LineKind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .addition:
            return [.foregroundColor: NSColor.systemGreen,
                    .backgroundColor: NSColor.systemGreen.withAlphaComponent(0.09)]
        case .deletion:
            return [.foregroundColor: NSColor.systemRed,
                    .backgroundColor: NSColor.systemRed.withAlphaComponent(0.08)]
        case .hunk:
            return [.foregroundColor: NSColor.systemBlue,
                    .backgroundColor: NSColor.systemBlue.withAlphaComponent(0.09)]
        case .header:
            return [.foregroundColor: NSColor.secondaryLabelColor,
                    .backgroundColor: NSColor.systemPurple.withAlphaComponent(0.05)]
        case .notice:
            return [.foregroundColor: NSColor.systemOrange,
                    .backgroundColor: NSColor.systemOrange.withAlphaComponent(0.08)]
        case .context:
            return [.foregroundColor: NSColor.labelColor]
        }
    }

    nonisolated private static func hunkRanges(_ line: String) -> (old: Int?, new: Int?) {
        let pattern = #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let oldRange = Range(match.range(at: 1), in: line),
              let newRange = Range(match.range(at: 2), in: line) else { return (nil, nil) }
        return (Int(line[oldRange]), Int(line[newRange]))
    }
}
