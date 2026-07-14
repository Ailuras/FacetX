import SwiftUI

private struct GitDiffLine: Identifiable {
    enum Kind {
        case addition
        case deletion
        case hunk
        case header
        case context
    }

    let id: Int
    let oldLine: Int?
    let newLine: Int?
    let text: String
    let kind: Kind
}

struct GitDiffView: View {
    let text: String
    let isLoading: Bool

    private var lines: [GitDiffLine] { Self.parse(text) }

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
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            diffRow(line)
                        }
                    }
                    .frame(minWidth: 720, alignment: .leading)
                    .textSelection(.enabled)
                }
                .thinScrollIndicators()
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.52))
    }

    private func diffRow(_ line: GitDiffLine) -> some View {
        HStack(alignment: .top, spacing: 0) {
            lineNumber(line.oldLine)
            lineNumber(line.newLine)
            Rectangle()
                .fill(markerColor(line.kind))
                .frame(width: 2)
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(foreground(line.kind))
                .padding(.horizontal, 10)
                .padding(.vertical, 2.5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(background(line.kind))
    }

    private func lineNumber(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? "")
            .font(.system(size: 9.5, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(width: 42, alignment: .trailing)
            .padding(.trailing, 7)
            .padding(.vertical, 3.5)
            .background(Color.primary.opacity(0.018))
    }

    private func background(_ kind: GitDiffLine.Kind) -> Color {
        switch kind {
        case .addition: return Color.green.opacity(0.085)
        case .deletion: return Color.red.opacity(0.075)
        case .hunk: return Color.blue.opacity(0.075)
        case .header: return Color.purple.opacity(0.045)
        case .context: return .clear
        }
    }

    private func markerColor(_ kind: GitDiffLine.Kind) -> Color {
        switch kind {
        case .addition: return .green
        case .deletion: return .red
        case .hunk: return .blue
        case .header: return .purple
        case .context: return .clear
        }
    }

    private func foreground(_ kind: GitDiffLine.Kind) -> Color {
        switch kind {
        case .addition: return .green
        case .deletion: return .red
        case .hunk: return .blue
        case .header: return .secondary
        case .context: return .primary
        }
    }

    private static func parse(_ raw: String) -> [GitDiffLine] {
        var oldLine: Int?
        var newLine: Int?
        return raw.components(separatedBy: .newlines).enumerated().map { index, text in
            if text.hasPrefix("@@") {
                let ranges = hunkRanges(text)
                oldLine = ranges.old
                newLine = ranges.new
                return GitDiffLine(id: index, oldLine: nil, newLine: nil, text: text, kind: .hunk)
            }
            if text.hasPrefix("diff --git") || text.hasPrefix("index ")
                || text.hasPrefix("--- ") || text.hasPrefix("+++ ")
                || text.hasPrefix("new file") || text.hasPrefix("deleted file")
                || text.hasPrefix("similarity index") || text.hasPrefix("rename ") {
                return GitDiffLine(id: index, oldLine: nil, newLine: nil, text: text, kind: .header)
            }
            if text.hasPrefix("+") {
                let current = newLine
                newLine = newLine.map { $0 + 1 }
                return GitDiffLine(id: index, oldLine: nil, newLine: current, text: text, kind: .addition)
            }
            if text.hasPrefix("-") {
                let current = oldLine
                oldLine = oldLine.map { $0 + 1 }
                return GitDiffLine(id: index, oldLine: current, newLine: nil, text: text, kind: .deletion)
            }
            let currentOld = oldLine
            let currentNew = newLine
            oldLine = oldLine.map { $0 + 1 }
            newLine = newLine.map { $0 + 1 }
            return GitDiffLine(id: index, oldLine: currentOld, newLine: currentNew, text: text, kind: .context)
        }
    }

    private static func hunkRanges(_ line: String) -> (old: Int?, new: Int?) {
        let pattern = #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let oldRange = Range(match.range(at: 1), in: line),
              let newRange = Range(match.range(at: 2), in: line) else { return (nil, nil) }
        return (Int(line[oldRange]), Int(line[newRange]))
    }
}
