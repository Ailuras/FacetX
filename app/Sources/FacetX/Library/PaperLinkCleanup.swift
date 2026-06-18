import Foundation

@MainActor
enum PaperLinkCleanup {
    @discardableResult
    static func removePaperIDs(_ paperIDs: [String],
                               projectStore: ProjectStore,
                               appSettings: AppSettings,
                               ek: EventKitService,
                               noteStore: ItemNoteStore = .shared) async -> Int {
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

            var metadata = item.facetItemMetadata()
            metadata.paperIDs = remainingPaperIDs
            noteStore.absorbLegacyNotes(id: metadata.noteID, legacyBody: item.notes ?? "")

            if await ek.rewriteItemMetadata(id: item.id, metadata: metadata) {
                changed += 1
            }
        }
        return changed
    }
}
