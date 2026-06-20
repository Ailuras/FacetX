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
@MainActor
final class MarkdownHighlighter: NSObject {
    /// Set by the editor so loads/programmatic refreshes can restyle.
    weak var textView: NSTextView?

    /// Restyle unless an IME composition is in flight. Safe to call from
    /// `textDidChange`, where `hasMarkedText()` reflects the settled state.
    func styleIfIdle(_ textView: NSTextView) {
        guard !textView.hasMarkedText(), let storage = textView.textStorage else { return }
        highlight(storage)
    }

    // ── Palette (colors only — never fonts for IME safety) ─────────────────────
    private let baseSize: CGFloat = 15
    private var baseFont: NSFont { .systemFont(ofSize: baseSize) }
    private let textColor = NSColor.labelColor

    /// Structural punctuation markers
    private let markerColor = NSColor.tertiaryLabelColor
    private let headingColor = NSColor.systemBlue
    private let codeColor = NSColor.systemPink
    private let linkColor = NSColor.linkColor
    private let quoteColor = NSColor.secondaryLabelColor
    private let listMarkerColor = NSColor.systemOrange
    private let mathColor = NSColor.systemPurple
    private let tagColor = NSColor.systemTeal
    private let completedTaskColor = NSColor.systemGreen

    // ── Precompiled patterns ────────────────────────────────────────────────────
    
    // Multi-line block structures
    private let fencedCodeRE = try! NSRegularExpression(pattern: "(?s)(```.*?```|```.*?\\z|~~~.*?~~~|~~~.*?\\z)")
    private let blockMathRE = try! NSRegularExpression(pattern: "(?s)(\\$\\$\\s*.*?\\s*\\$\\$|\\$\\$\\s*.*?\\z)")

    private let headingRE = try! NSRegularExpression(pattern: "^(#{1,6})(\\s+)")
    
    // Checkbox tasks (unordered and ordered)
    private let taskUnorderedRE = try! NSRegularExpression(pattern: "^(\\s*[-*+])(\\s+)(\\[)([ xX])(\\])(\\s+)")
    private let taskOrderedRE = try! NSRegularExpression(pattern: "^(\\s*\\d+\\.)(\\s+)(\\[)([ xX])(\\])(\\s+)")
    
    // Normal list items
    private let unorderedRE = try! NSRegularExpression(pattern: "^(\\s*)([-*+])(\\s+)")
    private let orderedRE = try! NSRegularExpression(pattern: "^(\\s*)(\\d+\\.)(\\s+)")
    
    // Inline elements
    private let inlineCodeRE = try! NSRegularExpression(pattern: "`([^`\\n]+)`")
    private let linkRE = try! NSRegularExpression(pattern: "\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)")
    private let boldRE = try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)(\\1)")
    private let italicRE = try! NSRegularExpression(pattern: "(?<![\\*_\\w])([*_])(?=\\S)(.+?)(?<=\\S)\\1(?![\\*_\\w])")
    private let strikeRE = try! NSRegularExpression(pattern: "(~~)(?=\\S)(.+?)(?<=\\S)(~~)")
    
    // LaTeX math blocks and inline math
    private let inlineMathRE = try! NSRegularExpression(pattern: "(?<!\\$)\\$(?!\\s)([^$\\n]+?)(?<!\\s)\\$(?!\\d)")
    
    // Tags like #tag (must start with word/tag characters and not be inside headers)
    private let tagRE = try! NSRegularExpression(pattern: "(?<![\\w#])#([a-zA-Z_0-9\\u4e00-\\u9fa5\\-]+)")

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

        var codeRanges: [NSRange] = [] // protect code spans from other highlights
        var mathRanges: [NSRange] = [] // protect math spans from other highlights
        
        // 1. Process block-level fenced code and block math first via full-document regexes
        fencedCodeRE.enumerateMatches(in: nsText as String, range: full) { match, _, _ in
            guard let match else { return }
            let matchRange = match.range
            let matchedStr = nsText.substring(with: matchRange)
            
            storage.addAttribute(.foregroundColor, value: self.codeColor, range: matchRange)
            self.color(storage, self.markerColor, matchRange.location, min(3, matchRange.length))
            if matchedStr.hasSuffix("```") && matchRange.length >= 6 {
                self.color(storage, self.markerColor, NSMaxRange(matchRange) - 3, 3)
            } else if matchedStr.hasSuffix("~~~") && matchRange.length >= 6 {
                self.color(storage, self.markerColor, NSMaxRange(matchRange) - 3, 3)
            }
            codeRanges.append(matchRange)
        }

        blockMathRE.enumerateMatches(in: nsText as String, range: full) { match, _, _ in
            guard let match, !self.intersects(match.range, codeRanges) else { return }
            let matchRange = match.range
            let matchedStr = nsText.substring(with: matchRange)
            
            storage.addAttribute(.foregroundColor, value: self.mathColor, range: matchRange)
            self.color(storage, self.markerColor, matchRange.location, min(2, matchRange.length))
            if matchedStr.hasSuffix("$$") && matchRange.length >= 4 {
                self.color(storage, self.markerColor, NSMaxRange(matchRange) - 2, 2)
            }
            mathRanges.append(matchRange)
        }

        // 2. Style regular line-scoped blocks, skipping lines within block code/math
        styleBlocks(storage, nsText: nsText, full: full, codeRanges: codeRanges, mathRanges: mathRanges)
        
        // 3. Style inline elements
        styleInline(storage, nsText: nsText, full: full, codeRanges: &codeRanges, mathRanges: &mathRanges)

        storage.endEditing()

        textView?.typingAttributes = [.font: baseFont, .foregroundColor: textColor]
    }

    // ── Block constructs (line scoped) ─────────────────────────────────────────

    private func styleBlocks(_ storage: NSTextStorage,
                             nsText: NSString,
                             full: NSRange,
                             codeRanges: [NSRange],
                             mathRanges: [NSRange]) {
        nsText.enumerateSubstrings(in: full, options: [.byLines]) { substring, lineRange, _, _ in
            // Skip lines that fall inside fenced code blocks or block math
            if self.intersects(lineRange, codeRanges) || self.intersects(lineRange, mathRanges) {
                return
            }

            guard let line = substring else { return }
            let lineLen = (line as NSString).length
            let nsRange = NSRange(location: 0, length: lineLen)

            // Headings
            if let m = self.headingRE.firstMatch(in: line, range: nsRange) {
                let markerLen = min(m.range.length, lineLen)
                self.color(storage, self.markerColor, lineRange.location, markerLen)
                let textStart = lineRange.location + markerLen
                self.color(storage, self.headingColor, textStart, lineRange.length - markerLen)
                return
            }

            // Checkbox tasks (unordered)
            if let m = self.taskUnorderedRE.firstMatch(in: line, range: nsRange) {
                let markerRange = NSRange(location: lineRange.location + m.range(at: 1).location, length: m.range(at: 1).length)
                let openBracketRange = NSRange(location: lineRange.location + m.range(at: 3).location, length: m.range(at: 3).length)
                let statusRange = NSRange(location: lineRange.location + m.range(at: 4).location, length: m.range(at: 4).length)
                let closeBracketRange = NSRange(location: lineRange.location + m.range(at: 5).location, length: m.range(at: 5).length)

                self.color(storage, self.listMarkerColor, markerRange.location, markerRange.length)
                self.color(storage, self.markerColor, openBracketRange.location, openBracketRange.length)
                self.color(storage, self.markerColor, closeBracketRange.location, closeBracketRange.length)

                let statusChar = (line as NSString).substring(with: m.range(at: 4))
                if statusChar.lowercased() == "x" {
                    self.color(storage, self.completedTaskColor, statusRange.location, statusRange.length)
                    let contentStart = lineRange.location + m.range.lowerBound + m.range.length
                    let contentLen = lineRange.length - (m.range.lowerBound + m.range.length)
                    if contentLen > 0 {
                        let textRange = NSRange(location: contentStart, length: contentLen)
                        storage.addAttribute(.foregroundColor, value: self.quoteColor, range: textRange)
                        storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
                    }
                } else {
                    self.color(storage, self.textColor, statusRange.location, statusRange.length)
                }
                return
            }

            // Checkbox tasks (ordered)
            if let m = self.taskOrderedRE.firstMatch(in: line, range: nsRange) {
                let markerRange = NSRange(location: lineRange.location + m.range(at: 1).location, length: m.range(at: 1).length)
                let openBracketRange = NSRange(location: lineRange.location + m.range(at: 3).location, length: m.range(at: 3).length)
                let statusRange = NSRange(location: lineRange.location + m.range(at: 4).location, length: m.range(at: 4).length)
                let closeBracketRange = NSRange(location: lineRange.location + m.range(at: 5).location, length: m.range(at: 5).length)

                self.color(storage, self.listMarkerColor, markerRange.location, markerRange.length)
                self.color(storage, self.markerColor, openBracketRange.location, openBracketRange.length)
                self.color(storage, self.markerColor, closeBracketRange.location, closeBracketRange.length)

                let statusChar = (line as NSString).substring(with: m.range(at: 4))
                if statusChar.lowercased() == "x" {
                    self.color(storage, self.completedTaskColor, statusRange.location, statusRange.length)
                    let contentStart = lineRange.location + m.range.lowerBound + m.range.length
                    let contentLen = lineRange.length - (m.range.lowerBound + m.range.length)
                    if contentLen > 0 {
                        let textRange = NSRange(location: contentStart, length: contentLen)
                        storage.addAttribute(.foregroundColor, value: self.quoteColor, range: textRange)
                        storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
                    }
                } else {
                    self.color(storage, self.textColor, statusRange.location, statusRange.length)
                }
                return
            }

            // Blockquotes
            if let r = line.range(of: "^\\s*>+\\s?", options: .regularExpression) {
                let markerLen = line.distance(from: line.startIndex, to: r.upperBound)
                self.color(storage, self.markerColor, lineRange.location, markerLen)
                self.color(storage, self.quoteColor, lineRange.location + markerLen, lineRange.length - markerLen)
                return
            }

            // Horizontal rules
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                storage.addAttribute(.foregroundColor, value: self.markerColor, range: lineRange)
                return
            }

            // Normal list markers
            if let m = self.unorderedRE.firstMatch(in: line, range: nsRange) {
                self.color(storage, self.listMarkerColor,
                           lineRange.location + m.range(at: 2).location, m.range(at: 2).length)
            } else if let m = self.orderedRE.firstMatch(in: line, range: nsRange) {
                self.color(storage, self.listMarkerColor,
                           lineRange.location + m.range(at: 2).location, m.range(at: 2).length)
            }
        }
    }

    // ── Inline spans (document scoped) ─────────────────────────────────────────

    private func styleInline(_ storage: NSTextStorage,
                             nsText: NSString,
                             full: NSRange,
                             codeRanges: inout [NSRange],
                             mathRanges: inout [NSRange]) {
        var protectedRanges = codeRanges + mathRanges

        // 1. Inline code
        inlineCodeRE.enumerateMatches(in: nsText as String, range: full) { match, _, _ in
            guard let match, !self.intersects(match.range, protectedRanges) else { return }
            storage.addAttribute(.foregroundColor, value: self.codeColor, range: match.range)
            self.color(storage, self.markerColor, match.range.location, 1)
            self.color(storage, self.markerColor, NSMaxRange(match.range) - 1, 1)
            protectedRanges.append(match.range)
        }

        // 2. Inline math
        inlineMathRE.enumerateMatches(in: nsText as String, range: full) { match, _, _ in
            guard let match, !self.intersects(match.range, protectedRanges) else { return }
            storage.addAttribute(.foregroundColor, value: self.mathColor, range: match.range)
            self.color(storage, self.markerColor, match.range.location, 1)
            self.color(storage, self.markerColor, NSMaxRange(match.range) - 1, 1)
            protectedRanges.append(match.range)
        }

        // 3. Links
        linkRE.enumerateMatches(in: nsText as String, range: full) { match, _, _ in
            guard let match, !self.intersects(match.range, protectedRanges) else { return }
            storage.addAttribute(.foregroundColor, value: self.linkColor, range: match.range(at: 1))
            self.color(storage, self.markerColor, match.range.location,
                       match.range(at: 1).location - match.range.location)
            let urlStart = NSMaxRange(match.range(at: 1))
            self.color(storage, self.markerColor, urlStart, NSMaxRange(match.range) - urlStart)
            protectedRanges.append(match.range)
        }

        // 4. Tags like #tag
        tagRE.enumerateMatches(in: nsText as String, range: full) { match, _, _ in
            guard let match, !self.intersects(match.range, protectedRanges) else { return }
            storage.addAttribute(.foregroundColor, value: self.tagColor, range: match.range)
            self.color(storage, self.markerColor, match.range.location, 1) // dim the # marker
        }

        // 5. Emphasis
        for re in [boldRE, italicRE, strikeRE] {
            re.enumerateMatches(in: nsText as String, range: full) { match, _, _ in
                guard let match, !self.intersects(match.range, protectedRanges) else { return }
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
