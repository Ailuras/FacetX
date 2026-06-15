import XCTest
@testable import VellumX

@MainActor
final class PaperStoreCollectionsTests: XCTestCase {
    func testCreateCollectionTrimsNameAndBuildsSubtree() throws {
        let store = PaperStore(databaseURL: try temporaryDatabaseURL(self))

        let parent = try XCTUnwrap(store.createCollection(name: "  Parent  ", color: "blue", icon: "book"))
        let child = try XCTUnwrap(store.createCollection(name: "  Child  ", parentId: parent.id))

        XCTAssertEqual(parent.name, "Parent")
        XCTAssertEqual(child.name, "Child")
        XCTAssertEqual(store.collectionSubtreeIds(parent.id), Set([parent.id, child.id]))
        XCTAssertNil(store.createCollection(name: "   "))
    }

    func testDeleteCollectionRemovesWholeSubtreeMembershipOnly() throws {
        let store = PaperStore(databaseURL: try temporaryDatabaseURL(self))
        _ = store.addOrUpdate(papers: [makePaper(id: "p1", title: "Paper One")])

        let parent = try XCTUnwrap(store.createCollection(name: "Parent"))
        let child = try XCTUnwrap(store.createCollection(name: "Child", parentId: parent.id))
        let sibling = try XCTUnwrap(store.createCollection(name: "Sibling"))

        store.addPaperToCollection(paperId: "p1", collectionId: child.id)
        store.addPaperToCollection(paperId: "p1", collectionId: sibling.id)
        store.deleteCollection(id: parent.id)

        XCTAssertFalse(store.allCollections.contains { $0.id == parent.id || $0.id == child.id })
        XCTAssertTrue(store.allCollections.contains { $0.id == sibling.id })
        XCTAssertEqual(store.papers.first?.collectionIds, [sibling.id])
    }

}
