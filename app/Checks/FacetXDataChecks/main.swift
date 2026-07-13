import Foundation
import SQLite3

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

@main
struct FacetXDataChecks {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FacetXDataChecks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let readme = root.appendingPathComponent("README.md")
        try "# Test\n".write(to: readme, atomically: true, encoding: .utf8)
        let created = try RepositoryDocumentStore.create(
            repositoryPath: root.path,
            title: "Weekly Plan",
            body: "# Weekly Plan\n"
        )
        check(created.relativePath == ".facetx/weekly-plan.md", "document creation should use .facetx")
        let createdBody = try RepositoryDocumentStore.read(repositoryPath: root.path, relativePath: created.relativePath)
        check(createdBody == "# Weekly Plan\n",
              "created document should be readable")
        try RepositoryDocumentStore.save(repositoryPath: root.path, relativePath: created.relativePath, body: "updated")
        let updatedBody = try RepositoryDocumentStore.read(repositoryPath: root.path, relativePath: created.relativePath)
        check(updatedBody == "updated",
              "document update should replace content")
        let listed = try RepositoryDocumentStore.list(repositoryPath: root.path).map(\.relativePath)
        check(Set(listed) == Set(["README.md", ".facetx/weekly-plan.md"]),
              "listing should include only supported documents: \(listed)")
        check(!RepositoryDocumentStore.isValid(relativePath: "/tmp/outside.md"), "absolute paths must be rejected")
        check(!RepositoryDocumentStore.isValid(relativePath: ".facetx/../outside.md"), "parent traversal must be rejected")
        check(!RepositoryDocumentStore.isValid(relativePath: "docs/outside.md"), "writes outside .facetx must be rejected")

        let linkedRepository = root.appendingPathComponent("linked-repository", isDirectory: true)
        let outsideDirectory = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: linkedRepository, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: linkedRepository.appendingPathComponent(".facetx"),
            withDestinationURL: outsideDirectory
        )
        do {
            try RepositoryDocumentStore.save(
                repositoryPath: linkedRepository.path,
                relativePath: ".facetx/escaped.md",
                body: "outside"
            )
            fatalError("symlink escapes must be rejected")
        } catch RepositoryDocumentStore.StoreError.invalidPath {
            check(!FileManager.default.fileExists(atPath: outsideDirectory.appendingPathComponent("escaped.md").path),
                  "rejected symlink writes must not create files outside the repository")
        }

        let databaseURL = root.appendingPathComponent("item-store.db")
        let store = ItemStore(databaseURL: databaseURL)
        let itemID = UUID().uuidString
        store.saveAll(id: itemID, body: "details", tags: ["read"], paperIDs: ["paper-1"], commits: ["repo@abc"])
        store.setDocumentPaths([created.relativePath, created.relativePath], for: itemID)
        check(store.paperIDs(for: itemID) == ["paper-1"], "paper relation should be stored")
        check(store.commits(for: itemID) == ["repo@abc"], "commit relation should be stored")
        check(store.documentPaths(for: itemID) == [created.relativePath], "document relations should be de-duplicated")
        store.recordFocusSession(
            targetID: itemID,
            projectPrefix: "Test",
            title: "Read",
            kind: "task",
            startedAt: Date(),
            seconds: 600
        )
        store.deleteLocalState(for: itemID)
        check(!store.exists(id: itemID), "deleting a work item should remove local details")
        check(store.paperIDs(for: itemID).isEmpty && store.commits(for: itemID).isEmpty && store.documentPaths(for: itemID).isEmpty,
              "deleting a work item should remove every resource relation")
        check(store.focusTotalsByTarget()[itemID] == nil, "deleting a work item should remove focus summaries")

        let otherID = UUID().uuidString
        store.saveAll(id: otherID, body: "", tags: [], paperIDs: ["paper-2"], commits: [])
        store.removePaperReferences(paperIDs: ["paper-2"])
        check(store.paperIDs(for: otherID).isEmpty, "deleting literature should remove backlinks")

        var db: OpaquePointer?
        check(sqlite3_open(databaseURL.path, &db) == SQLITE_OK, "check database should open")
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=('item_' || 'notes')", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        check(sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_int(statement, 0) == 0,
              "removed content tables must not exist")

        print("FacetXDataChecks OK")
    }
}
