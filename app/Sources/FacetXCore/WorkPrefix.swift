import Foundation

/// The work-association contract: an item belongs to a work when its
/// title starts with `WorkName` followed by a colon.
///
/// Tolerance rules:
/// - Accept both the ASCII colon `:` and the fullwidth `：` on read.
/// - Titles can contain newlines; only the first line is considered for the
///   prefix.
public enum WorkPrefix {
    public static let asciiColon: Character = ":"
    public static let fullwidthColon: Character = "："

    private static func firstLine(in rawTitle: String) -> Substring {
        let end = rawTitle.firstIndex(of: "\n") ?? rawTitle.endIndex
        return rawTitle[..<end]
    }

    /// Extract the work name from an item title, or nil if it has no prefix.
    public static func workName(of rawTitle: String) -> String? {
        let firstLine = firstLine(in: rawTitle)
        guard let idx = firstLine.firstIndex(where: { $0 == asciiColon || $0 == fullwidthColon })
        else { return nil }
        let name = firstLine[..<idx].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// Strip the `Work:` prefix to get the human-facing item text.
    public static func contentBody(of rawTitle: String) -> String {
        guard let idx = firstLine(in: rawTitle).firstIndex(where: { $0 == asciiColon || $0 == fullwidthColon })
        else { return rawTitle }
        let after = rawTitle[rawTitle.index(after: idx)...]
        return after.trimmingCharacters(in: .whitespaces)
    }

    /// Compose a title that carries the work prefix (always ASCII colon).
    public static func makeTitle(work: String, content: String) -> String {
        "\(work)\(asciiColon) \(content)"
    }
}
