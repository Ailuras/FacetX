import Foundation

/// The project-association contract: an item belongs to a project when its
/// title starts with `ProjectName` followed by a colon.
///
/// Tolerance rules (validated against real data via the EventKit probes):
/// - Accept BOTH the ASCII colon `:` and the fullwidth `：` on read; existing
///   calendar data uses `：` while new items are written with `:`.
/// - Titles can contain newlines (real reminder titles do) — only the first
///   line is considered for the prefix.
enum ProjectPrefix {
    static let asciiColon: Character = ":"
    static let fullwidthColon: Character = "："

    /// Extract the project name from an item title, or nil if it has no prefix.
    static func projectName(of rawTitle: String) -> String? {
        let firstLine = rawTitle.split(separator: "\n", maxSplits: 1,
                                       omittingEmptySubsequences: false).first.map(String.init) ?? rawTitle
        guard let idx = firstLine.firstIndex(where: { $0 == asciiColon || $0 == fullwidthColon })
        else { return nil }
        let name = firstLine[..<idx].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// Does this title belong to the given project? Case-sensitive on the name,
    /// colon-tolerant on the separator.
    static func belongs(title: String, toProject project: String) -> Bool {
        guard let name = projectName(of: title) else { return false }
        return name == project
    }

    /// Strip the `Project:` prefix to get the human-facing item text.
    static func contentBody(of rawTitle: String) -> String {
        guard let idx = rawTitle.firstIndex(where: { $0 == asciiColon || $0 == fullwidthColon })
        else { return rawTitle }
        let after = rawTitle[rawTitle.index(after: idx)...]
        return after.trimmingCharacters(in: .whitespaces)
    }

    /// Compose a title that carries the project prefix (always ASCII colon).
    static func makeTitle(project: String, content: String) -> String {
        "\(project)\(asciiColon) \(content)"
    }
}
