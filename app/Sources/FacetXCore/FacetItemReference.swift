import Foundation

/// The complete FacetX identity stored in EventKit notes.
///
/// Work-item details and resource relationships live in ItemStore; EventKit
/// carries only this UUID so reminders and events can be hydrated reliably.
public struct FacetItemReference: Equatable, Sendable {
    public let itemID: String

    public init(itemID: String = UUID().uuidString) {
        precondition(UUID(uuidString: itemID) != nil, "Facet item identity must be a UUID")
        self.itemID = itemID
    }

    public static func parse(notes: String?) -> FacetItemReference? {
        guard let value = notes?.trimmingCharacters(in: .whitespacesAndNewlines),
              UUID(uuidString: value) != nil else {
            return nil
        }
        return FacetItemReference(itemID: value)
    }
}
