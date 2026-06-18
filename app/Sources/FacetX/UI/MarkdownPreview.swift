import SwiftUI

/// A lightweight, line-based markdown renderer for note previews.
///
/// Handles the common block elements (ATX headings, bullet/numbered lists,
/// blockquotes, horizontal rules) and delegates inline styling (bold, italic,
/// code, links) to `AttributedString(markdown:)`. This is intentionally simple;
/// it is the shared preview surface for the note detail pane and editor.
struct MarkdownPreview: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, line in
                lineView(line)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var blocks: [String] { text.components(separatedBy: "\n") }

    @ViewBuilder private func lineView(_ raw: String) -> some View {
        let line = raw
        if line.hasPrefix("### ") {
            Text(inline(String(line.dropFirst(4)))).font(.system(size: 14, weight: .semibold))
        } else if line.hasPrefix("## ") {
            Text(inline(String(line.dropFirst(3)))).font(.system(size: 16, weight: .bold))
        } else if line.hasPrefix("# ") {
            Text(inline(String(line.dropFirst(2)))).font(.system(size: 19, weight: .bold))
        } else if line == "---" || line == "***" || line == "___" {
            Divider().padding(.vertical, 2)
        } else if line.hasPrefix("> ") {
            HStack(spacing: 6) {
                Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3)
                Text(inline(String(line.dropFirst(2)))).foregroundStyle(.secondary)
            }
        } else if let bullet = bulletContent(line) {
            HStack(alignment: .top, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                Text(inline(bullet))
            }
        } else if let (number, content) = numberedContent(line) {
            HStack(alignment: .top, spacing: 6) {
                Text("\(number).").foregroundStyle(.secondary).monospacedDigit()
                Text(inline(content))
            }
        } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
            Spacer().frame(height: 4)
        } else {
            Text(inline(line))
        }
    }

    private func bulletContent(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private func numberedContent(_ line: String) -> (Int, String)? {
        guard let dot = line.firstIndex(of: "."),
              let number = Int(line[line.startIndex..<dot]),
              line.index(after: dot) < line.endIndex,
              line[line.index(after: dot)] == " " else { return nil }
        return (number, String(line[line.index(dot, offsetBy: 2)...]))
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(s)
    }
}
