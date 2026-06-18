import Foundation

/// The four user-facing project element types.
///
/// Underneath there are only two EventKit kinds (`reminder` / `event`); `paper`
/// and `note` are reminders/events that additionally carry linked local content
/// (a paper record in `PaperStore`, or a markdown file in the project folder).
/// `facetKind` is the single place that maps an item to one of these four, so
/// callers never re-derive the classification from `kind` + linked-id checks.
public enum FacetKind: String, CaseIterable, Sendable {
    case task
    case event
    case paper
    case note
}

public extension ProjectItem {
    /// Classifies this item into one of the four FacetX element types.
    var facetKind: FacetKind {
        switch kind {
        case .reminder:
            return linkedPaperIDs.isEmpty ? .task : .paper
        case .event:
            return isNote ? .note : .event
        }
    }
}
