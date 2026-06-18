import AppKit
import SwiftUI

/// Controls a `MarkdownEditor`'s text view so a SwiftUI toolbar can apply
/// formatting to the current selection. The editor registers its text view here
/// on appearance; the buttons call these methods.
@MainActor
final class MarkdownEditorController: ObservableObject {
    fileprivate weak var textView: NSTextView?

    func bold() { wrap("**", "**") }
    func italic() { wrap("*", "*") }
    func code() { wrap("`", "`") }
    func heading() { prefixLine("## ") }
    func bulletList() { prefixLine("- ") }
    func quote() { prefixLine("> ") }

    func link() {
        guard let tv = textView else { return }
        let selected = (tv.string as NSString).substring(with: tv.selectedRange())
        let label = selected.isEmpty ? "text" : selected
        replaceSelection(with: "[\(label)](url)")
    }

    /// Wrap the current selection (or insertion point) with `prefix`/`suffix`.
    fileprivate func wrap(_ prefix: String, _ suffix: String) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let ns = tv.string as NSString
        let selected = ns.substring(with: range)
        let replacement = "\(prefix)\(selected)\(suffix)"
        if tv.shouldChangeText(in: range, replacementString: replacement) {
            tv.textStorage?.replaceCharacters(in: range, with: replacement)
            // Place the cursor inside the markers when nothing was selected.
            let cursor = range.location + (selected.isEmpty ? prefix.count : replacement.count)
            tv.setSelectedRange(NSRange(location: cursor, length: 0))
            tv.didChangeText()
        }
    }

    /// Insert `marker` at the start of each line touched by the selection.
    fileprivate func prefixLine(_ marker: String) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let lineRange = ns.lineRange(for: tv.selectedRange())
        let block = ns.substring(with: lineRange)
        let prefixed = block
            .components(separatedBy: "\n")
            .enumerated()
            .map { index, line in
                // Don't add a trailing marker to the empty piece after a final newline.
                (index == block.components(separatedBy: "\n").count - 1 && line.isEmpty) ? line : marker + line
            }
            .joined(separator: "\n")
        if tv.shouldChangeText(in: lineRange, replacementString: prefixed) {
            tv.textStorage?.replaceCharacters(in: lineRange, with: prefixed)
            tv.setSelectedRange(NSRange(location: lineRange.location, length: (prefixed as NSString).length))
            tv.didChangeText()
        }
    }

    fileprivate func replaceSelection(with string: String) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        if tv.shouldChangeText(in: range, replacementString: string) {
            tv.textStorage?.replaceCharacters(in: range, with: string)
            tv.setSelectedRange(NSRange(location: range.location + (string as NSString).length, length: 0))
            tv.didChangeText()
        }
    }
}

/// A plain-text markdown editor backed by NSTextView, with Cmd+B / Cmd+I /
/// Cmd+K shortcuts. Pairs with a live `MarkdownPreview` for real-time rendering.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: MarkdownEditorController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true

        // Build the text system manually so the view is a proper first responder
        // and tracks the scroll view's width.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let formatting = FormattingTextView(frame: NSRect(origin: .zero, size: scroll.contentSize),
                                            textContainer: container)
        formatting.controller = controller
        formatting.delegate = context.coordinator
        textStorage.delegate = context.coordinator.highlighter
        formatting.isEditable = true
        formatting.isSelectable = true
        formatting.isRichText = false
        formatting.allowsUndo = true
        formatting.isAutomaticQuoteSubstitutionEnabled = false
        formatting.isAutomaticDashSubstitutionEnabled = false
        formatting.font = MarkdownSyntaxHighlighter.bodyFont
        let typingAttributes: [NSAttributedString.Key: Any] = [
            .font: MarkdownSyntaxHighlighter.bodyFont,
            .foregroundColor: NSColor.labelColor
        ]
        formatting.typingAttributes = typingAttributes
        formatting.textContainerInset = NSSize(width: 6, height: 8)
        formatting.drawsBackground = false
        formatting.minSize = NSSize(width: 0, height: 0)
        formatting.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        formatting.isVerticallyResizable = true
        formatting.isHorizontallyResizable = false
        formatting.autoresizingMask = [NSView.AutoresizingMask.width]
        formatting.string = text

        scroll.documentView = formatting
        controller.textView = formatting
        context.coordinator.highlighter.highlight(formatting.textStorage!)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        if controller.textView !== textView {
            controller.textView = textView
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: MarkdownEditor
        let highlighter = MarkdownSyntaxHighlighter()
        init(_ parent: MarkdownEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

/// NSTextView subclass that turns Cmd+B/I/K into markdown formatting.
private final class FormattingTextView: NSTextView {
    weak var controller: MarkdownEditorController?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch chars {
        case "b": controller?.bold(); return true
        case "i": controller?.italic(); return true
        case "k": controller?.link(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}
