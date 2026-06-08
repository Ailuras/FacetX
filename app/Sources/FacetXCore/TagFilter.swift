import Foundation

public enum TagFilterState: Sendable {
    case neutral, included, excluded
}

/// Multi-state tag filter: a tag can be included (must match), excluded
/// (must not match), or neutral (no constraint). Tap-cycling a tag walks
/// neutral → included → excluded → neutral.
public struct TagFilter: Equatable, Sendable {
    public var included: Set<String>
    public var excluded: Set<String>

    public init(included: Set<String> = [], excluded: Set<String> = []) {
        self.included = included
        self.excluded = excluded
    }

    public var isEmpty: Bool { included.isEmpty && excluded.isEmpty }

    public func state(of tag: String) -> TagFilterState {
        if included.contains(tag) { return .included }
        if excluded.contains(tag) { return .excluded }
        return .neutral
    }

    public mutating func cycle(_ tag: String) {
        switch state(of: tag) {
        case .neutral:
            included.insert(tag)
        case .included:
            included.remove(tag)
            excluded.insert(tag)
        case .excluded:
            excluded.remove(tag)
        }
    }

    public mutating func clear() {
        included.removeAll()
        excluded.removeAll()
    }

    /// An item passes the filter when:
    ///   - none of its tags are excluded, AND
    ///   - either nothing is included, or at least one included tag matches.
    public func matches(_ item: ProjectItem) -> Bool {
        if !excluded.isEmpty {
            for tag in item.tags where excluded.contains(tag) { return false }
        }
        if included.isEmpty { return true }
        for tag in item.tags where included.contains(tag) { return true }
        return false
    }
}
