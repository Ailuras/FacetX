import AppKit

/// Applies live, in-place typographic highlighting to a markdown `NSTextStorage`
/// so the editor reads like a rendered document while staying fully editable:
/// headings grow, emphasis takes real bold/italic, code and quotes get their own
/// treatment, and the syntax markers (`#`, `**`, backticks, …) dim into the
/// background instead of being hidden — the active text never changes, only its
/// attributes, which keeps CJK / IME composition safe.
///
/// The whole document is restyled on each character edit. Notes are small, and
/// attribute-only passes don't re-trigger character editing, so this stays cheap
/// and keeps multi-line constructs (fenced code) correct without range bookkeeping.
///
/// Not `@MainActor`-isolated: `NSTextStorageDelegate` is a nonisolated protocol
/// and its callbacks already arrive on the main thread, so isolating the class
/// only fights Swift 6 conformance checking for no benefit.
final class MarkdownHighlighter: NSObject, NSTextStorageDelegate {
    /// The text view is consulted so we never restyle mid-composition, which is
    /// what previously corrupted Chinese/Japanese/Korean input.
    weak var textView: NSTextView?

    // ── Typography ────────────────────────────────────────────────────────────
    private let baseSize: CGFloat = 15
    private var baseFont: NSFont { .systemFont(ofSize: baseSize) }
    private var monoFont: NSFont { .monospacedSystemFont(ofSize: baseSize - 1, weight: .regular) }

    private let markerColor = NSColor.tertiaryLabelColor
    private let codeColor = NSColor.systemPink
    private let codeBackground = NSColor.quaternaryLabelColor.withAlphaComponent(0.18)
    private let linkColor = NSColor.linkColor
    private let quoteColor = NSColor.secondaryLabelColor

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 26
        case 2: return 22
        case 3: return 19
        case 4: return 17
        case 5: return 16
        default: return baseSize
        }
    }

    // ── Precompiled inline patterns ───────────────────────────────────────────
    private let headingRE = try! NSRegularExpression(pattern: "^(#{1,6})\\s+")
    private let unorderedRE = try! NSRegularExpression(pattern: "^(\\s*)([-*+])\\s+")
    private let orderedRE = try! NSRegularExpression(pattern: "^(\\s*)(\\d+\\.)\\s+")
    private let inlineCodeRE = try! NSRegularExpression(pattern: "`([^`\\n]+)`")
    private let linkRE = try! NSRegularExpression(pattern: "\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)")
    private let boldRE = try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)(\\1)")
    private let italicRE = try! NSRegularExpression(pattern: "(?<![\\*_\\w])([*_])(?=\\S)(.+?)(?<=\\S)\\1(?![\\*_\\w])")
    private let strikeRE = try! NSRegularExpression(pattern: "(~~)(?=\\S)(.+?)(?<=\\S)(~~)")

    // ── Entry points ──────────────────────────────────────────────────────────

    func textStorage(_ textStorage: NSTextStorage,
                     didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange,
                     changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        // Leave composing text untouched so IME underlines/commits survive.
        if textView?.hasMarkedText() == true { return }
        highlight(textStorage)
    }

    /// Restyle the entire storage. Safe to call after programmatic text loads.
    func highlight(_ storage: NSTextStorage) {
        let nsText = storage.string as NSString
        let full = NSRange(location: 0, length: nsText.length)
        guard full.length > 0 else { return }

        storage.beginEditing()
        storage.setAttributes([.font: baseFont, .foregroundColor: NSColor.labelColor], range: full)

        // Ranges occupied by code (inline or fenced) — emphasis must not touch them.
        var codeRanges: [NSRange] = []

        styleBlocks(storage, nsText: nsText, full: full, codeRanges: &codeRanges)
        styleInline(storage, nsText: nsText, full: full, codeRanges: &codeRanges)

        storage.endEditing()

        // Keep the insertion point neutral so freshly typed text isn't carried
        // along in a previous span's styling before the next restyle lands.
        textView?.typingAttributes = [.font: baseFont, .foregroundColor: NSColor.labelColor]
    }

    // ── Block constructs (line scoped) ─────────────────────────────────────────

    private func styleBlocks(_ storage: NSTextStorage,
                            nsText: NSString,
                            full: NSRange,
                            codeRanges: inout [NSRange]) {
        var inFence = false
        // Capture into locals; enumerateSubstrings's closure is non-escaping.
        var collectedCode: [NSRange] = []

        nsText.enumerateSubstrings(in: full, options: [.byLines]) { substring, lineRange, _, _ in
            guard let line = substring else { return }
            let lineNS = line as NSString
            let lineLen = lineNS.length

            // Fenced code blocks.
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFence.toggle()
                storage.addAttributes([.font: self.monoFont, .foregroundColor: self.markerColor],
                                      range: lineRange)
                collectedCode.append(lineRange)
                return
            }
            if inFence {
                storage.addAttributes([.font: self.monoFont, .backgroundColor: self.codeBackground],
                                      range: lineRange)
                collectedCode.append(lineRange)
                return
            }

            // Headings.
            if let m = self.headingRE.firstMatch(in: line, range: NSRange(location: 0, length: lineLen)) {
                let level = m.range(at: 1).length
                let font = NSFont.systemFont(ofSize: self.headingSize(level), weight: .bold)
                storage.addAttribute(.font, value: font, range: lineRange)
                let markerLen = min(m.range.length, lineLen)
                storage.addAttribute(.foregroundColor, value: self.markerColor,
                                     range: NSRange(location: lineRange.location, length: markerLen))
                return
            }

            // Blockquotes.
            if line.hasPrefix(">") {
                storage.addAttribute(.foregroundColor, value: self.quoteColor, range: lineRange)
                let style = NSMutableParagraphStyle()
                style.firstLineHeadIndent = 6
                style.headIndent = 16
                storage.addAttribute(.paragraphStyle, value: style, range: lineRange)
                return
            }

            // Horizontal rules.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                storage.addAttribute(.foregroundColor, value: self.markerColor, range: lineRange)
                return
            }

            // List markers.
            let nsRange = NSRange(location: 0, length: lineLen)
            if let m = self.unorderedRE.firstMatch(in: line, range: nsRange) {
                let markerRange = NSRange(location: lineRange.location + m.range(at: 2).location,
                                          length: m.range(at: 2).length)
                storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: markerRange)
            } else if let m = self.orderedRE.firstMatch(in: line, range: nsRange) {
                let markerRange = NSRange(location: lineRange.location + m.range(at: 2).location,
                                          length: m.range(at: 2).length)
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: markerRange)
            }
        }

        codeRanges.append(contentsOf: collectedCode)
    }

    // ── Inline spans (document scoped) ─────────────────────────────────────────

    private func styleInline(_ storage: NSTextStorage,
                            nsText: NSString,
                            full: NSRange,
                            codeRanges: inout [NSRange]) {
        // Inline code first so it's both styled and protected from emphasis.
        inlineCodeRE.enumerateMatches(in: nsText as String, range: full) { match, _, _ in
            guard let match else { return }
            storage.addAttributes([.font: self.monoFont,
                                   .foregroundColor: self.codeColor,
                                   .backgroundColor: self.codeBackground],
                                  range: match.range)
            self.dim(storage, NSRange(location: match.range.location, length: 1))
            self.dim(storage, NSRange(location: NSMaxRange(match.range) - 1, length: 1))
            codeRanges.append(match.range)
        }

        let protectedCode = codeRanges

        // Links: color the label, dim brackets and the URL.
        linkRE.enumerateMatches(in: nsText as String, range: full) { match, _, _ in
            guard let match, !self.intersects(match.range, protectedCode) else { return }
            storage.addAttribute(.foregroundColor, value: self.linkColor, range: match.range(at: 1))
            // Everything outside the label text dims (brackets, parens, url).
            self.dim(storage, NSRange(location: match.range.location,
                                      length: match.range(at: 1).location - match.range.location))
            let urlStart = NSMaxRange(match.range(at: 1))
            self.dim(storage, NSRange(location: urlStart, length: NSMaxRange(match.range) - urlStart))
        }

        applyEmphasis(storage, regex: boldRE, range: full, protected: protectedCode, trait: .boldFontMask)
        applyEmphasis(storage, regex: italicRE, range: full, protected: protectedCode, trait: .italicFontMask)

        strikeRE.enumerateMatches(in: nsText as String, range: full) { match, _, _ in
            guard let match, !self.intersects(match.range, protectedCode) else { return }
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
            self.dim(storage, match.range(at: 1))
            self.dim(storage, match.range(at: 3))
        }
    }

    /// Add a font trait across `range` while preserving each run's size/family,
    /// then dim the surrounding markers.
    private func applyEmphasis(_ storage: NSTextStorage,
                              regex: NSRegularExpression,
                              range: NSRange,
                              protected: [NSRange],
                              trait: NSFontTraitMask) {
        let text = storage.string
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, !self.intersects(match.range, protected) else { return }
            let inner = match.range(at: 2)
            storage.enumerateAttribute(.font, in: inner, options: []) { value, subRange, _ in
                let current = (value as? NSFont) ?? self.baseFont
                let styled = NSFontManager.shared.convert(current, toHaveTrait: trait)
                storage.addAttribute(.font, value: styled, range: subRange)
            }
            // Dim the opening/closing markers (groups 1 and 3, or `inner` edges).
            let markerLen = match.range(at: 1).length
            self.dim(storage, NSRange(location: match.range.location, length: markerLen))
            self.dim(storage, NSRange(location: NSMaxRange(match.range) - markerLen, length: markerLen))
        }
    }

    private func dim(_ storage: NSTextStorage, _ range: NSRange) {
        guard range.length > 0, range.location >= 0,
              NSMaxRange(range) <= storage.length else { return }
        storage.addAttribute(.foregroundColor, value: markerColor, range: range)
    }

    private func intersects(_ range: NSRange, _ others: [NSRange]) -> Bool {
        others.contains { NSIntersectionRange($0, range).length > 0 }
    }
}
