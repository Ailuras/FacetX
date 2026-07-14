import Foundation
import SQLite3

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

@main
struct FacetXDataChecks {
    @MainActor
    static func main() async throws {
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
        let renamed = try RepositoryDocumentStore.rename(
            repositoryPath: root.path,
            relativePath: created.relativePath,
            title: "Research Roadmap"
        )
        check(renamed.relativePath == ".facetx/research-roadmap.md", "rename should stay inside .facetx")
        check(!RepositoryDocumentStore.exists(repositoryPath: root.path, relativePath: created.relativePath),
              "rename should remove the old document path")
        let renamedBody = try RepositoryDocumentStore.read(repositoryPath: root.path, relativePath: renamed.relativePath)
        check(renamedBody == "updated",
              "rename should preserve document content")
        let restored = try RepositoryDocumentStore.rename(
            repositoryPath: root.path,
            relativePath: renamed.relativePath,
            title: "Weekly Plan"
        )
        check(restored.relativePath == created.relativePath, "rename should support restoring the original name")
        let disposable = try RepositoryDocumentStore.create(repositoryPath: root.path, title: "Disposable")
        try RepositoryDocumentStore.delete(repositoryPath: root.path, relativePath: disposable.relativePath)
        check(!RepositoryDocumentStore.exists(repositoryPath: root.path, relativePath: disposable.relativePath),
              "delete should remove a .facetx document")
        do {
            try RepositoryDocumentStore.delete(repositoryPath: root.path, relativePath: "README.md")
            fatalError("README deletion must be rejected")
        } catch RepositoryDocumentStore.StoreError.protectedDocument {}
        check(!RepositoryDocumentStore.isValid(relativePath: "/tmp/outside.md"), "absolute paths must be rejected")
        check(!RepositoryDocumentStore.isValid(relativePath: ".facetx/../outside.md"), "parent traversal must be rejected")
        check(!RepositoryDocumentStore.isValid(relativePath: "docs/outside.md"), "writes outside .facetx must be rejected")

        let parsedStatus = LocalGitRepository.parseStatus("MM both.txt\n?? new.txt\nR  old.txt -> renamed.txt\n")
        check(parsedStatus.contains { $0.path == "both.txt" && $0.area == .staged },
              "a dual-state path should expose its staged change")
        check(parsedStatus.contains { $0.path == "both.txt" && $0.area == .unstaged },
              "a dual-state path should expose its unstaged change")
        check(parsedStatus.contains { $0.path == "new.txt" && $0.state == .untracked },
              "untracked paths should remain actionable")
        check(parsedStatus.contains { $0.path == "renamed.txt" && $0.originalPath == "old.txt" },
              "renames should preserve both paths")

        let gitRoot = root.appendingPathComponent("git-workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: gitRoot, withIntermediateDirectories: true)
        try runGit(["init"], at: gitRoot)
        try runGit(["config", "user.name", "FacetX Checks"], at: gitRoot)
        try runGit(["config", "user.email", "facetx-checks@example.invalid"], at: gitRoot)
        let tracked = gitRoot.appendingPathComponent("tracked.md")
        try "initial\n".write(to: tracked, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.md"], at: gitRoot)
        try runGit(["commit", "-m", "initial"], at: gitRoot)
        try "initial\nchanged\n".write(to: tracked, atomically: true, encoding: .utf8)
        try "new\n".write(to: gitRoot.appendingPathComponent("new.md"), atomically: true, encoding: .utf8)

        var gitStatus = await LocalGitRepository.gitStatus(rootPath: gitRoot.path)
        check(gitStatus.contains { $0.path == "tracked.md" && $0.area == .unstaged },
              "working-tree modifications should be detected")
        check(gitStatus.contains { $0.path == "new.md" && $0.state == .untracked },
              "working-tree untracked files should be detected")
        if let trackedChange = gitStatus.first(where: { $0.path == "tracked.md" }) {
            let diff = await LocalGitRepository.diff(rootPath: gitRoot.path, entry: trackedChange)
            check(diff.contains("+changed"), "working-tree diff should include added content")
        } else {
            fatalError("tracked change missing")
        }
        let stageResult = await LocalGitRepository.stage(rootPath: gitRoot.path, path: "tracked.md")
        check(stageResult.succeeded, "stage should succeed")
        gitStatus = await LocalGitRepository.gitStatus(rootPath: gitRoot.path)
        check(gitStatus.contains { $0.path == "tracked.md" && $0.area == .staged },
              "staged changes should be detected")
        let unstageResult = await LocalGitRepository.unstage(rootPath: gitRoot.path, path: "tracked.md")
        check(unstageResult.succeeded, "unstage should succeed")
        let stageAllResult = await LocalGitRepository.stageAll(rootPath: gitRoot.path)
        check(stageAllResult.succeeded, "stage all should succeed")
        let commitResult = await LocalGitRepository.commit(rootPath: gitRoot.path, title: "second", body: "body")
        check(commitResult.succeeded, "commit should succeed: \(commitResult.message)")
        let history = await LocalGitRepository.gitLog(rootPath: gitRoot.path)
        check(history.first?.summary == "second", "history should return the newest commit first")
        let branch = await LocalGitRepository.branchState(rootPath: gitRoot.path)
        check(branch.current != nil && branch.localBranches.contains(branch.current!),
              "branch inspection should return the checked-out branch")
        let activity = await LocalGitRepository.activity(
            rootPath: gitRoot.path,
            since: Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        )
        check(activity.reduce(0) { $0 + $1.commitCount } == 2,
              "activity should count repository commits by day")

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

    private static func runGit(_ arguments: [String], at directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            throw NSError(
                domain: "FacetXDataChecks.Git",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "git failed"]
            )
        }
    }
}
