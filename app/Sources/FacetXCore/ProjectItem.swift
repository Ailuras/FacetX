import Foundation

/// A reminder or calendar event, flattened for the UI and tagged with the
/// project it belongs to (via the title prefix).
///
/// Lives in FacetXCore — free of EventKit/SwiftUI — so the pure ordering and
/// grouping logic in `ItemArrangement` can be unit-checked. `EventKitService`
/// builds these value types from EKReminder/EKEvent inside its fetch callbacks.
public struct ProjectItem: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case reminder, event }
    public let id: String          // EventKit calendarItemIdentifier
    public let kind: Kind
    public let rawTitle: String
    public let projectPrefix: String   // the project prefix extracted from the title
    public let content: String     // title with the project prefix stripped
    public let containerName: String   // reminder list / calendar = functional zone
    public let isCompleted: Bool
    public let date: Date?         // due date (reminder) or start date (event)
    public let notes: String?      // user-facing notes / description, metadata stripped
    public let tags: [String]      // FacetX tags parsed from the native notes metadata block
    public let priority: Int       // priority value (0 = none, 1-4 = high, 5 = med, 9 = low)
    public let url: URL?           // URL associated with the item
    public let hasTime: Bool       // true when the date carries an explicit time component
    public let isAllDay: Bool      // true for all-day events (events only; always false for reminders)
    public let endDate: Date?      // end date for events (nil for reminders)

    public init(id: String, kind: Kind, rawTitle: String, projectPrefix: String,
                 content: String, containerName: String, isCompleted: Bool, date: Date?,
                 notes: String?, tags: [String] = [], priority: Int, url: URL?,
                 hasTime: Bool = false,
                 isAllDay: Bool = false, endDate: Date? = nil) {
        self.id = id
        self.kind = kind
        self.rawTitle = rawTitle
        self.projectPrefix = projectPrefix
        self.content = content
        self.containerName = containerName
        self.isCompleted = isCompleted
        self.date = date
        self.notes = notes
        self.tags = tags
        self.priority = priority
        self.url = url
        self.hasTime = hasTime
        self.isAllDay = isAllDay
        self.endDate = endDate
    }

    /// Build a copy with a different kind. Used as a drag-preview placeholder
    /// when cross-section dragging in the All view — the real EventKit
    /// conversion happens on drop and replaces this stand-in with a fresh id.
    public func replacingKind(_ kind: Kind) -> ProjectItem {
        ProjectItem(
            id: id,
            kind: kind,
            rawTitle: rawTitle,
            projectPrefix: projectPrefix,
            content: content,
            containerName: containerName,
            isCompleted: isCompleted,
            date: date,
            notes: notes,
            tags: tags,
            priority: priority,
            url: url,
            hasTime: hasTime,
            isAllDay: isAllDay,
            endDate: endDate
        )
    }

    public func replacingDate(_ date: Date, endDate: Date? = nil, hasTime: Bool? = nil) -> ProjectItem {
        ProjectItem(
            id: id,
            kind: kind,
            rawTitle: rawTitle,
            projectPrefix: projectPrefix,
            content: content,
            containerName: containerName,
            isCompleted: isCompleted,
            date: date,
            notes: notes,
            tags: tags,
            priority: priority,
            url: url,
            hasTime: hasTime ?? self.hasTime,
            isAllDay: isAllDay,
            endDate: endDate ?? self.endDate
        )
    }

    /// Whether this item matches a free-text search over its content, notes and
    /// container name. An empty/whitespace query matches everything, so callers
    /// can filter unconditionally.
    public func matches(searchQuery query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return content.lowercased().contains(q)
            || (notes?.lowercased().contains(q) ?? false)
            || tags.contains { $0.lowercased().contains(q) }
            || containerName.lowercased().contains(q)
    }
}
