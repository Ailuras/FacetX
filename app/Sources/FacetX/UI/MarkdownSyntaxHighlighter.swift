import AppKit

/// Applies markdown styling to an NSTextView's text storage as the user types,
/// Obsidian "live preview" style: the source text stays editable and the
/// markers remain visible but dimmed, while the content they wrap is rendered
/// (headings enlarged, bold/italic/code styled, lists and quotes tinted).
///
/// This is not full WYSIWYG — markers are not hidden — but it gives real
/// inline rendering in a single editor without a separate preview pane.
final class MarkdownSyntaxHighlighter: NSObject, NSTextStorageDelegate {
    /// Re-entrancy guard: editing attributes inside the delegate callback would
    /// otherwise trigger another didProcessEditing pass.
    private var isHighlighting = false
    /// The editor, so we can skip restyling while an input method is composing
    /// marked text (otherwise Chinese/Japanese/etc. composition is broken).
    weak var textView: NSTextView?

    static var bodyFont: NSFont { NSFont.systemFont(ofSize: 13) }

    nonisolated(unsafe) private static let headingRegex = try! NSRegularExpression(pattern: "^(#{1,6})[ \t]+(.+)$", options: [.anchorsMatchLines])
    nonisolated(unsafe) private static let boldRegex = try! NSRegularExpression(pattern: "(\\*\\*|__)(.+?)(\\1)")
    nonisolated(unsafe) private static let italicRegex = try! NSRegularExpression(pattern: "(?<![\\*_])([\\*_])(?![\\*_])(.+?)([\\*_])")
    nonisolated(unsafe) private static let codeRegex = try! NSRegularExpression(pattern: "`([^`\n]+)`")
    nonisolated(unsafe) private static let linkRegex = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)")
    nonisolated(unsafe) private static let listRegex = try! NSRegularExpression(pattern: "^[ \t]*([-*+]|\\d+\\.)[ \t]+", options: [.anchorsMatchLines])
    nonisolated(unsafe) private static let quoteRegex = try! NSRegularExpression(pattern: "^[ \t]*(>+)[ \t]?.*$", options: [.anchorsMatchLines])

    func textStorage(_ textStorage: NSTextStorage,
                     didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange,
                     changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !isHighlighting else { return }
        // Don't touch the storage mid-composition or the input method's marked
        // text gets torn down on every keystroke (breaks Chinese/Japanese input).
        if textView?.hasMarkedText() == true { return }
        isHighlighting = true
        defer { isHighlighting = false }
        highlight(textStorage)
    }

    func highlight(_ storage: NSTextStorage) {
        let ns = storage.string as NSString
        let full = NSRange(location: 0, length: ns.length)
        let body = Self.bodyFont
        let dim = NSColor.tertiaryLabelColor
        let codeColor = NSColor.systemPink
        let linkColor = NSColor.controlAccentColor

        storage.beginEditing()
        storage.setAttributes([.font: body, .foregroundColor: NSColor.labelColor], range: full)

        // Headings — enlarge the whole line by level, dim the leading hashes.
        Self.headingRegex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let m = match else { return }
            let hashes = m.range(at: 1)
            let level = hashes.length
            let size: CGFloat = [22, 19, 17, 15, 14, 13][min(level - 1, 5)]
            let font = NSFont.boldSystemFont(ofSize: size)
            storage.addAttribute(.font, value: font, range: m.range)
            storage.addAttribute(.foregroundColor, value: dim, range: hashes)
        }

        // Quotes and list markers.
        Self.quoteRegex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let m = match else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range)
        }
        Self.listRegex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let m = match else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: m.range(at: 1))
        }

        // Inline: bold, italic, code, links.
        Self.boldRegex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let m = match else { return }
            applyTrait(.boldFontMask, base: body, to: storage, range: m.range(at: 2))
            dimMarkers(storage, m.range(at: 1), m.range(at: 3), color: dim)
        }
        Self.italicRegex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let m = match else { return }
            applyTrait(.italicFontMask, base: body, to: storage, range: m.range(at: 2))
            dimMarkers(storage, m.range(at: 1), m.range(at: 3), color: dim)
        }
        Self.codeRegex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let m = match else { return }
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular), range: m.range)
            storage.addAttribute(.foregroundColor, value: codeColor, range: m.range)
        }
        Self.linkRegex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
            guard let m = match else { return }
            storage.addAttribute(.foregroundColor, value: linkColor, range: m.range(at: 1))
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 1))
            // Dim the [], () and url.
            storage.addAttribute(.foregroundColor, value: dim, range: NSRange(location: m.range.location, length: m.range(at: 1).location - m.range.location))
        }

        storage.endEditing()
    }

    private func applyTrait(_ trait: NSFontTraitMask, base: NSFont, to storage: NSTextStorage, range: NSRange) {
        guard range.length > 0 else { return }
        let font = NSFontManager.shared.convert(base, toHaveTrait: trait)
        storage.addAttribute(.font, value: font, range: range)
    }

    private func dimMarkers(_ storage: NSTextStorage, _ a: NSRange, _ b: NSRange, color: NSColor) {
        if a.length > 0 { storage.addAttribute(.foregroundColor, value: color, range: a) }
        if b.length > 0 { storage.addAttribute(.foregroundColor, value: color, range: b) }
    }
}
