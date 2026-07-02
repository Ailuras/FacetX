import FacetXCore
import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let facetXProjectItem = UTType(exportedAs: "com.facetx.project-item")
}

/// A self-contained drag snapshot. The visible chip uses human-readable fields;
/// the hidden reference id keeps duplicate titles unambiguous for tool calls.
struct AssistantItemMention: Codable, Hashable, Identifiable, Sendable {
    let eventKitID: String
    let stableID: String?
    let kind: String
    let projectPrefix: String
    let title: String
    let containerName: String
    let date: Date?
    let endDate: Date?
    let hasTime: Bool
    let isAllDay: Bool
    let isCompleted: Bool
    let priority: Int
    let tags: [String]
    let isNote: Bool

    var id: String { referenceID }
    var referenceID: String { stableID ?? "eventkit:\(eventKitID)" }

    var systemImage: String {
        if isNote { return "note.text" }
        return kind == "task" ? "checkmark.circle" : "calendar"
    }

    init(item: ProjectItem) {
        eventKitID = item.id
        stableID = item.facetID
        kind = item.kind == .reminder ? "task" : "event"
        projectPrefix = item.projectPrefix
        title = item.content
        containerName = item.containerName
        date = item.date
        endDate = item.endDate
        hasTime = item.hasTime
        isAllDay = item.isAllDay
        isCompleted = item.isCompleted
        priority = item.priority
        tags = item.tags
        isNote = item.isNote
    }

    var promptObject: [String: Any] {
        let formatter = ISO8601DateFormatter()
        var object: [String: Any] = [
            "reference_id": referenceID,
            "type": isNote ? "note" : kind,
            "project": projectPrefix,
            "title": title,
            "container": containerName,
            "completed": isCompleted,
            "priority": priority,
            "tags": tags,
        ]
        if let date { object["start_or_due"] = formatter.string(from: date) }
        if let endDate { object["end"] = formatter.string(from: endDate) }
        object["has_time"] = hasTime
        object["all_day"] = isAllDay
        return object
    }
}
