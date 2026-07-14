import Foundation

/// A reminder or calendar event, flattened for the UI and tagged with the
/// work it belongs to (via the title prefix).
///
/// Lives in FacetXCore — free of EventKit/SwiftUI — so the pure ordering and
/// grouping logic in `ItemArrangement` can be unit-checked. `EventKitService`
/// builds these value types from EKReminder/EKEvent inside its fetch callbacks.
public struct WorkItem: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case reminder, event }
    public let id: String          // EventKit calendarItemIdentifier
    public let kind: Kind
    public let rawTitle: String
    public let workPrefix: String   // the work prefix extracted from the title
    public let content: String     // title with the work prefix stripped
    public let containerName: String   // reminder list / calendar = functional zone
    public let isCompleted: Bool
    public let date: Date?         // due date (reminder) or start date (event)
    public let notes: String?      // user-facing notes / description, metadata stripped
    public let tags: [String]      // FacetX tags parsed from local database
    public let priority: Int       // priority value (0 = none, 1-4 = high, 5 = med, 9 = low)
    public let url: URL?           // URL associated with the item
    public let hasTime: Bool       // true when the date carries an explicit time component
    public let isAllDay: Bool      // true for all-day events (events only; always false for reminders)
    public let endDate: Date?      // end date for events (nil for reminders)
    public let facetID: String?    // stable FacetX item identity stored in EventKit notes metadata
    public let linkedPaperIDs: [String]
    public let linkedCommits: [String]
    public let linkedDocumentPaths: [String]
    public let isPinned: Bool      // user-set pin; floats the item to the top of its section

    public init(id: String, kind: Kind, rawTitle: String, workPrefix: String,
                 content: String, containerName: String, isCompleted: Bool, date: Date?,
                 notes: String?, tags: [String] = [], priority: Int, url: URL?,
                 hasTime: Bool = false,
                 isAllDay: Bool = false, endDate: Date? = nil,
                 facetID: String? = nil,
                 linkedPaperIDs: [String] = [], linkedCommits: [String] = [],
                 linkedDocumentPaths: [String] = [],
                 isPinned: Bool = false) {
        self.id = id
        self.kind = kind
        self.rawTitle = rawTitle
        self.workPrefix = workPrefix
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
        self.facetID = facetID
        self.linkedPaperIDs = linkedPaperIDs
        self.linkedCommits = linkedCommits
        self.linkedDocumentPaths = linkedDocumentPaths
        self.isPinned = isPinned
    }

    /// Whether a timed item is past due and still open. Computed, never stored:
    /// events use their end (falling back to start), reminders their due date.
    /// Timed items go overdue the moment they pass; all-day / undated items only
    /// once the whole day is behind us.
    public var isOverdue: Bool {
        guard !isCompleted else { return false }
        guard let due = (kind == .event ? (endDate ?? date) : date) else { return false }
        let timed = kind == .event ? !isAllDay : hasTime
        let now = Date()
        if timed { return due < now }
        let calendar = Calendar.current
        return calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
    }

    /// Build a copy with a different kind. Used as a drag-preview placeholder
    /// when cross-section dragging in the All view — the real EventKit
    /// conversion happens on drop and replaces this stand-in with a fresh id.
    public func replacingKind(_ kind: Kind) -> WorkItem {
        WorkItem(
            id: id,
            kind: kind,
            rawTitle: rawTitle,
            workPrefix: workPrefix,
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
            endDate: endDate,
            facetID: facetID,
            linkedPaperIDs: linkedPaperIDs,
            linkedCommits: linkedCommits,
            linkedDocumentPaths: linkedDocumentPaths,
            isPinned: isPinned
        )
    }

    public func replacingDate(_ date: Date, endDate: Date? = nil, hasTime: Bool? = nil) -> WorkItem {
        WorkItem(
            id: id,
            kind: kind,
            rawTitle: rawTitle,
            workPrefix: workPrefix,
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
            endDate: endDate ?? self.endDate,
            facetID: facetID,
            linkedPaperIDs: linkedPaperIDs,
            linkedCommits: linkedCommits,
            linkedDocumentPaths: linkedDocumentPaths,
            isPinned: isPinned
        )
    }

    public func replacingSchedule(_ date: Date, endDate: Date?, hasTime: Bool, isAllDay: Bool) -> WorkItem {
        WorkItem(
            id: id,
            kind: kind,
            rawTitle: rawTitle,
            workPrefix: workPrefix,
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
            endDate: endDate,
            facetID: facetID,
            linkedPaperIDs: linkedPaperIDs,
            linkedCommits: linkedCommits,
            linkedDocumentPaths: linkedDocumentPaths,
            isPinned: isPinned
        )
    }

    /// Apply locally-stored state (pin flag + resolved completion) onto an item
    /// freshly built from EventKit. Used by the hydration pass in `EventKitService`.
    public func applyingLocalState(isPinned: Bool, isCompleted: Bool) -> WorkItem {
        WorkItem(
            id: id,
            kind: kind,
            rawTitle: rawTitle,
            workPrefix: workPrefix,
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
            endDate: endDate,
            facetID: facetID,
            linkedPaperIDs: linkedPaperIDs,
            linkedCommits: linkedCommits,
            linkedDocumentPaths: linkedDocumentPaths,
            isPinned: isPinned
        )
    }

    public func facetItemReference() -> FacetItemReference {
        FacetItemReference(itemID: facetID ?? UUID().uuidString)
    }

    public func withMergedMetadata(notes: String?, tags: [String], paperIDs: [String], commits: [String], documentPaths: [String] = []) -> WorkItem {
        WorkItem(
            id: id,
            kind: kind,
            rawTitle: rawTitle,
            workPrefix: workPrefix,
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
            endDate: endDate,
            facetID: facetID,
            linkedPaperIDs: paperIDs,
            linkedCommits: commits,
            linkedDocumentPaths: documentPaths,
            isPinned: isPinned
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
