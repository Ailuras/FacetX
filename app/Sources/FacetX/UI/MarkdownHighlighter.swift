import AppKit

/// Applies live **syntax highlighting** to a markdown `NSTextStorage`: it stays a
/// plain source editor with one uniform font and size — nothing is "rendered".
/// Only foreground colors change, so markdown markers (`#`, `**`, backticks, `>`,
/// list bullets, link punctuation …) and their content get distinct colors, the
/// way a code editor highlights source. No font scaling, weight/slant changes,
/// indentation, or background blocks. The active text never changes, only its
/// color attributes, which keeps CJK / IME composition safe.
///
/// The whole document is restyled on each change. Notes are small, so this stays
/// cheap and keeps multi-line constructs (fenced code) correct without bookkeeping.
///
/// IME safety: highlighting is driven from the text view's `textDidChange`
/// (see `styleIfIdle`), *not* from `NSTextStorageDelegate`. During an IME
/// composition the text-storage edit fires before the text view records its
/// marked range, so `hasMarkedText()` is unreliable inside that delegate and a
/// restyle there corrupts in-progress Chinese/Japanese/Korean input. By the time
/// `textDidChange` arrives the marked range is set, so the guard below is
/// trustworthy and we simply skip until the composition commits.
final class MarkdownHighlighter: NSObject {
    /// Set by the editor so loads/programmatic refreshes can restyle.
    weak var textView: NSTextView?

    /// Restyle unless an IME composition is in flight. Safe to call from
    /// `textDidChange`, where `hasMarkedText()` reflects the settled state.
    func styleIfIdle(_ textView: NSTextView) {
        guard !textView.hasMarkedText(), let storage = textView.textStorage else { return }
        highlight(storage)
    }

    // ── Palette (colors only — never fonts) ─────────────────────────────────────
    private let baseSize: CGFloat = 15
    private var baseFont: NSFont { .systemFont(ofSize: baseSize) }
    private let textColor = NSColor.labelColor

    /// Structural punctuation: `#`, `**`, `*`, `_`, `~~`, backticks, `>`,
    /// list bullets, link brackets/parens, fences, rules.
    private let markerColor = NSColor.tertiaryLabelColor
    private let headingColor = NSColor.systemBlue
    private let codeColor = NSColor.systemPink
    private let linkColor = NSColor.linkColor
    private let quoteColor = NSColor.secondaryLabelColor
    private let listMarkerColor = NSColor.systemOrange

    // ── Precompiled patterns ────────────────────────────────────────────────────
    private let headingRE = try! NSRegularExpression(pattern: "^(#{1,6})(\\s+)")
    private let unorderedRE = try! NSRegularExpression(pattern: "^(\\s*)([-*+])(\\s+)")
    private let orderedRE = try! NSRegularExpression(pattern: "^(\\s*)(\\d+\\.)(\\s+)")
    private let inlineCodeRE = try! NSRegularExpression(pattern: "`([^`\\n]+)`")
    private let linkRE = try! NSRegularExpression(pattern: "\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)")
    private let boldRE = try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)(\\1)")
    private let italicRE = try! NSRegularExpression(pattern: "(?<![\\*_\\w])([*_])(?=\\S)(.+?)(?<=\\S)\\1(?![\\*_\\w])")
    private let strikeRE = try! NSRegularExpression(pattern: "(~~)(?=\\S)(.+?)(?<=\\S)(~~)")

    // ── Entry point ─────────────────────────────────────────────────────────────

    /// Restyle the entire storage. Safe to call after programmatic text loads.
    func highlight(_ storage: NSTextStorage) {
        let nsText = storage.string as NSString
        let full = NSRange(location: 0, length: nsText.length)
        guard full.length > 0 else { return }

        storage.beginEditing()
        // Reset to one uniform font/size and the base color. Highlighting only
        // recolors from here on — it never touches the font again.
        storage.setAttributes([.font: baseFont, .foregroundColor: textColor], range: full)

        var codeRanges: [NSRange] = [] // protect code spans from emphasis recoloring
        styleBlocks(storage, nsText: nsText, full: full, codeRanges: &codeRanges)
        styleInline(storage, nsText: nsText, full: full, codeRanges: &codeRanges)

        storage.endEditing()

        textView?.typingAttributes = [.font: baseFont, .foregroundColor: textColor]
    }

    // ── Block constructs (line scoped) ─────────────────────────────────────────

    private func styleBlocks(_ storage: NSTextStorage,
                            nsText: NSString,
                            full: NSRange,
                            codeRanges: inout [NSRange]) {
        var inFence = false
        var collectedCode: [NSRange] = []

        nsText.enumerateSubstrings(in: full, options: [.byLines]) { substring, lineRange, _, _ in
            guard let line = substring else { return }
            let lineLen = (line as NSString).length

            // Fenced code blocks: delimiter lines are punctuation; inner lines are code.
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFence.toggle()
                storage.addAttribute(.foregroundColor, value: self.markerColor, range: lineRange)
                collectedCode.append(lineRange)
                return
            }
            if inFence {
                storage.addAttribute(.foregroundColor, value: self.codeColor, range: lineRange)
                collectedCode.append(lineRange)
                return
            }

            let nsRange = NSRange(location: 0, length: lineLen)

            // Headings: dim the `#…` marker, color the heading text.
            if let m = self.headingRE.firstMatch(in: line, range: nsRange) {
                let markerLen = min(m.range.length, lineLen)
                self.color(storage, self.markerColor, lineRange.location, markerLen)
                let textStart = lineRange.location + markerLen
                self.color(storage, self.headingColor, textStart, lineRange.length - markerLen)
                return
            }

            // Blockquotes: dim the `>` marker, color the quoted text.
            if let r = line.range(of: "^\\s*>+\\s?", options: .regularExpression) {
                let markerLen = line.distance(from: line.startIndex, to: r.upperBound)
                self.color(storage, self.markerColor, lineRange.location, markerLen)
                self.color(storage, self.quoteColor, lineRange.location + markerLen, lineRange.length - markerLen)
                return
            }

            // Horizontal rules.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                storage.addAttribute(.foregroundColor, value: self.markerColor, range: lineRange)
                return
            }

            // List markers (bullet or number) — color only the marker.
            if let m = self.unorderedRE.firstMatch(in: line, range: nsRange) {
                self.color(storage, self.listMarkerColor,
                           lineRange.location + m.range(at: 2).location, m.range(at: 2).length)
            } else if let m = self.orderedRE.firstMatch(in: line, range: nsRange) {
                self.color(storage, self.listMarkerColor,
                           lineRange.location + m.range(at: 2).location, m.range(at: 2).length)
            }
        }

        codeRanges.append(contentsOf: collectedCode)
    }

    // ── Inline spans (document scoped) ─────────────────────────────────────────

    private func styleInline(_ storage: NSTextStorage,
                            nsText: NSString,
                            full: NSRange,
                            codeRanges: inout [NSRange]) {
        // Inline code first: color it and protect it from emphasis recoloring.
        inlineCodeRE.enumerateMatches(in: nsText as String, range: full) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.foregroundColor, value: self.codeColor, range: match.range)
            self.color(storage, self.markerColor, match.range.location, 1)
            self.color(storage, self.markerColor, NSMaxRange(match.range) - 1, 1)
            codeRanges.append(match.range)
        }
        let protectedCode = codeRanges

        // Links: color the label, dim the brackets/parens/url.
        linkRE.enumerateMatches(in: nsText as String, range: full) { match, _, _ in
            guard let match, !self.intersects(match.range, protectedCode) else { return }
            storage.addAttribute(.foregroundColor, value: self.linkColor, range: match.range(at: 1))
            self.color(storage, self.markerColor, match.range.location,
                       match.range(at: 1).location - match.range.location)
            let urlStart = NSMaxRange(match.range(at: 1))
            self.color(storage, self.markerColor, urlStart, NSMaxRange(match.range) - urlStart)
        }

        // Emphasis: dim the surrounding markers only — the content stays base text.
        for re in [boldRE, italicRE, strikeRE] {
            re.enumerateMatches(in: nsText as String, range: full) { match, _, _ in
                guard let match, !self.intersects(match.range, protectedCode) else { return }
                let markerLen = match.range(at: 1).length
                self.color(storage, self.markerColor, match.range.location, markerLen)
                self.color(storage, self.markerColor, NSMaxRange(match.range) - markerLen, markerLen)
            }
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────────────────

    private func color(_ storage: NSTextStorage, _ color: NSColor, _ location: Int, _ length: Int) {
        guard length > 0, location >= 0, location + length <= storage.length else { return }
        storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: location, length: length))
    }

    private func intersects(_ range: NSRange, _ others: [NSRange]) -> Bool {
        others.contains { NSIntersectionRange($0, range).length > 0 }
    }
}
