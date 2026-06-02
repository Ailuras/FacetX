import Foundation

/// FacetX-owned metadata stored inside EventKit's native notes field.
///
/// The user-facing notes are kept outside the metadata block. FacetX may add
/// fields inside the block without creating a second source of truth for item
/// content.
public struct FacetMetadata: Equatable, Sendable {
    public static let beginMarker = "FacetX-Metadata-Begin"
    public static let endMarker = "FacetX-Metadata-End"

    public var userNotes: String
    public var tags: [String]
    public var fields: [String: String]

    public init(userNotes: String = "", tags: [String] = [], fields: [String: String] = [:]) {
        self.userNotes = userNotes
        self.tags = Self.normalizedTags(tags)
        var fields = fields
        if self.tags.isEmpty {
            fields.removeValue(forKey: "tags")
        } else {
            fields["tags"] = self.tags.joined(separator: ", ")
        }
        self.fields = fields
    }

    public static func parse(notes: String?) -> FacetMetadata {
        guard let notes, !notes.isEmpty else { return FacetMetadata() }
        guard let begin = notes.range(of: beginMarker),
              let end = notes.range(of: endMarker, range: begin.upperBound..<notes.endIndex) else {
            return FacetMetadata(userNotes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let before = notes[..<begin.lowerBound]
        let after = notes[end.upperBound...]
        let userNotes = [String(before), String(after)]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let block = notes[begin.upperBound..<end.lowerBound]
        var fields: [String: String] = [:]
        for line in block.components(separatedBy: .newlines) {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { fields[key] = value }
        }

        return FacetMetadata(userNotes: userNotes,
                             tags: tags(from: fields["tags"] ?? ""),
                             fields: fields)
    }

    public static func compose(userNotes: String, metadata: FacetMetadata) -> String? {
        let trimmedNotes = userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        var fields = metadata.fields
        let tags = normalizedTags(metadata.tags)
        if tags.isEmpty {
            fields.removeValue(forKey: "tags")
        } else {
            fields["tags"] = tags.joined(separator: ", ")
        }

        let lines = fields.keys.sorted().compactMap { key -> String? in
            guard let value = fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return "\(key): \(value)"
        }

        if trimmedNotes.isEmpty && lines.isEmpty { return nil }
        guard !lines.isEmpty else { return trimmedNotes }

        let block = ([beginMarker] + lines + [endMarker]).joined(separator: "\n")
        return trimmedNotes.isEmpty ? block : "\(trimmedNotes)\n\n\(block)"
    }

    public static func tags(from text: String) -> [String] {
        normalizedTags(text.split { $0 == "," || $0 == "#" || $0.isNewline }.map(String.init))
    }

    public static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in tags {
            let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            guard !tag.isEmpty else { continue }
            let key = tag.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(tag)
        }
        return result
    }
}
