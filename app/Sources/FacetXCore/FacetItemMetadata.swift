import Foundation

public struct FacetItemMetadata: Equatable, Sendable {
    public var itemID: String

    // For convenience / compatibility with callers, we keep these properties in the struct
    // so method signatures and initialization don't require churn:
    public var paperIDs: [String]
    public var commits: [String]
    public var tags: [String]

    public init(itemID: String = UUID().uuidString,
                paperIDs: [String] = [],
                commits: [String] = [],
                tags: [String] = []) {
        self.itemID = itemID
        self.paperIDs = Self.normalizedList(paperIDs)
        self.commits = Self.normalizedList(commits)
        self.tags = FacetMetadata.normalizedTags(tags)
    }

    public static func parse(notes: String?) -> FacetItemMetadata? {
        guard let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty else { return nil }
        if UUID(uuidString: notes) != nil {
            return FacetItemMetadata(itemID: notes)
        }
        if notes.contains("FacetX-Metadata-Begin") {
            let parsed = FacetMetadata.parse(notes: notes)
            if let itemID = parsed.fields["item-id"] ?? parsed.fields["note-id"] {
                return FacetItemMetadata(
                    itemID: itemID,
                    paperIDs: [],
                    commits: [],
                    tags: parsed.tags
                )
            }
        }
        return nil
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
}
