import Foundation

/// Item-level FacetX metadata embedded in a Reminder/Calendar notes field.
///
/// EventKit remains the owner of the task/event. FacetX stores only durable
/// references here: a stable local item id, a local note id, and resource links.
public struct FacetItemMetadata: Equatable, Sendable {
    public static let kindValue = "item-v1"

    public static let kindKey = "facetx-kind"
    public static let itemIDKey = "item-id"
    public static let noteIDKey = "note-id"
    public static let papersKey = "papers"
    public static let commitsKey = "commits"

    public var itemID: String
    public var noteID: String
    public var paperIDs: [String]
    public var commits: [String]
    public var tags: [String]

    public init(itemID: String = UUID().uuidString,
                noteID: String = UUID().uuidString,
                paperIDs: [String] = [],
                commits: [String] = [],
                tags: [String] = []) {
        self.itemID = itemID
        self.noteID = noteID
        self.paperIDs = Self.normalizedList(paperIDs)
        self.commits = Self.normalizedList(commits)
        self.tags = FacetMetadata.normalizedTags(tags)
    }

    public static func parse(_ metadata: FacetMetadata) -> FacetItemMetadata? {
        guard metadata.fields[kindKey] == kindValue,
              let itemID = nonEmpty(metadata.fields[itemIDKey]),
              let noteID = nonEmpty(metadata.fields[noteIDKey]) else {
            return nil
        }
        return FacetItemMetadata(
            itemID: itemID,
            noteID: noteID,
            paperIDs: decodeList(metadata.fields[papersKey] ?? ""),
            commits: decodeList(metadata.fields[commitsKey] ?? ""),
            tags: metadata.tags
        )
    }

    public static func repairing(_ metadata: FacetMetadata) -> FacetItemMetadata {
        if let parsed = parse(metadata) {
            return parsed
        }
        return FacetItemMetadata(
            itemID: nonEmpty(metadata.fields[itemIDKey]) ?? UUID().uuidString,
            noteID: nonEmpty(metadata.fields[noteIDKey]) ?? UUID().uuidString,
            paperIDs: decodeList(metadata.fields[papersKey] ?? ""),
            commits: decodeList(metadata.fields[commitsKey] ?? ""),
            tags: metadata.tags
        )
    }

    public static func isCanonical(_ metadata: FacetMetadata) -> Bool {
        parse(metadata) != nil && metadata.userNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func facetMetadata() -> FacetMetadata {
        var fields: [String: String] = [
            Self.kindKey: Self.kindValue,
            Self.itemIDKey: itemID,
            Self.noteIDKey: noteID
        ]
        let papers = Self.encodeList(paperIDs)
        if !papers.isEmpty { fields[Self.papersKey] = papers }
        let commits = Self.encodeList(commits)
        if !commits.isEmpty { fields[Self.commitsKey] = commits }
        return FacetMetadata(tags: tags, fields: fields)
    }

    public func addingPaper(_ id: String) -> FacetItemMetadata {
        var copy = self
        copy.paperIDs = Self.normalizedList(copy.paperIDs + [id])
        return copy
    }

    public func removingPaper(_ id: String) -> FacetItemMetadata {
        var copy = self
        copy.paperIDs.removeAll { $0 == id }
        return copy
    }

    public func addingCommit(_ id: String) -> FacetItemMetadata {
        var copy = self
        copy.commits = Self.normalizedList(copy.commits + [id])
        return copy
    }

    public func removingCommit(_ id: String) -> FacetItemMetadata {
        var copy = self
        copy.commits.removeAll { $0 == id }
        return copy
    }

    public static func encodeList(_ values: [String]) -> String {
        normalizedList(values)
            .map { percentEncode($0) }
            .joined(separator: ",")
    }

    public static func decodeList(_ value: String) -> [String] {
        normalizedList(
            value.split(separator: ",")
                .map(String.init)
                .map { $0.removingPercentEncoding ?? $0 }
        )
    }

    private static func normalizedList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ",")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
