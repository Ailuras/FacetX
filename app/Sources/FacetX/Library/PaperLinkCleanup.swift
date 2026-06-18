import Foundation

@MainActor
enum PaperLinkCleanup {
    @discardableResult
    static func removePaperIDs(_ paperIDs: [String],
                               projectStore: ProjectStore,
                               appSettings: AppSettings,
                               ek: EventKitService,
                               itemStore: ItemStore = .shared) async -> Int {
        let targetIDs = Set(paperIDs)
        guard !targetIDs.isEmpty else { return 0 }

        let prefixes = Set(projectStore.projects.map(\.prefix))
        let linkedItems = await ek.itemsLinkedToPapers(
            forProjects: prefixes,
            enabledReminderLists: appSettings.effectiveReminderListNames,
            enabledCalendars: appSettings.effectiveCalendarNames
        )

        var changed = 0
        for item in linkedItems {
            let remainingPaperIDs = item.linkedPaperIDs.filter { !targetIDs.contains($0) }
            guard remainingPaperIDs.count != item.linkedPaperIDs.count else { continue }

            if let facetID = item.facetID {
                itemStore.setPaperIDs(remainingPaperIDs, for: facetID)
                changed += 1
            }
        }
        return changed
    }
}
