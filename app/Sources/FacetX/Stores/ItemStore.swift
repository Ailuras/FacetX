import Foundation
import Observation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
@Observable
final class ItemStore {
    static let shared = ItemStore()

    private var db: OpaquePointer?
    private let databaseURLOverride: URL?
    private(set) var version = 0
    private(set) var persistenceError: String?

    var dbURL: URL {
        if let databaseURLOverride { return databaseURLOverride }
        return AppSupport.directory().appendingPathComponent("item-notes.db")
    }

    private init() {
        databaseURLOverride = nil
        openDatabase()
        createTablesIfNeeded()
    }

    init(databaseURL: URL) {
        databaseURLOverride = databaseURL
        openDatabase()
        createTablesIfNeeded()
    }



    func exists(id: String) -> Bool {
        let sql = "SELECT 1 FROM items WHERE id = ? LIMIT 1"
        var stmt: OpaquePointer?
        var found = false
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                found = true
            }
        }
        sqlite3_finalize(stmt)
        return found
    }

    func isNote(for id: String) -> Bool {
        let sql = "SELECT is_note FROM items WHERE id = ? LIMIT 1"
        var stmt: OpaquePointer?
        var value = false
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                value = sqlite3_column_int(stmt, 0) != 0
            }
        }
        sqlite3_finalize(stmt)
        return value
    }

    func setIsNote(_ isNote: Bool, for id: String) {
        let sql = """
        INSERT INTO items (id, is_note, created_at, updated_at, last_seen_at)
        VALUES (?, ?, datetime('now'), datetime('now'), datetime('now'))
        ON CONFLICT(id) DO UPDATE SET
            is_note = excluded.is_note,
            updated_at = datetime('now'),
            last_seen_at = datetime('now')
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            persistenceError = databaseError("prepare save is_note")
            return
        }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, isNote ? 1 : 0)
        if sqlite3_step(stmt) == SQLITE_DONE {
            persistenceError = nil
            version += 1
        } else {
            persistenceError = databaseError("save is_note")
        }
        sqlite3_finalize(stmt)
    }

    func isPinned(for id: String) -> Bool {
        boolColumn("pinned", for: id)
    }

    func setPinned(_ pinned: Bool, for id: String) {
        setBoolColumn("pinned", value: pinned, for: id, action: "pinned")
    }

    func isCompleted(for id: String) -> Bool {
        boolColumn("completed", for: id)
    }

    func setCompleted(_ completed: Bool, for id: String) {
        setBoolColumn("completed", value: completed, for: id, action: "completed")
    }

    /// Reads a 0/1 integer column from the `items` row, defaulting to false when
    /// the row or value is absent. Column name is a compile-time literal (never
    /// user input), so interpolating it into the SQL is safe here.
    private func boolColumn(_ column: String, for id: String) -> Bool {
        let sql = "SELECT \(column) FROM items WHERE id = ? LIMIT 1"
        var stmt: OpaquePointer?
        var value = false
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                value = sqlite3_column_int(stmt, 0) != 0
            }
        }
        sqlite3_finalize(stmt)
        return value
    }

    private func setBoolColumn(_ column: String, value: Bool, for id: String, action: String) {
        let sql = """
        INSERT INTO items (id, \(column), created_at, updated_at, last_seen_at)
        VALUES (?, ?, datetime('now'), datetime('now'), datetime('now'))
        ON CONFLICT(id) DO UPDATE SET
            \(column) = excluded.\(column),
            updated_at = datetime('now'),
            last_seen_at = datetime('now')
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            persistenceError = databaseError("prepare save \(action)")
            return
        }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, value ? 1 : 0)
        if sqlite3_step(stmt) == SQLITE_DONE {
            persistenceError = nil
            version += 1
        } else {
            persistenceError = databaseError("save \(action)")
        }
        sqlite3_finalize(stmt)
    }

    func body(for id: String) -> String {
        let sql = "SELECT note_body FROM items WHERE id = ? LIMIT 1"
        var stmt: OpaquePointer?
        var value = ""
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                value = columnString(stmt, 0)
            }
        }
        sqlite3_finalize(stmt)
        return value
    }

    func save(id: String, body: String) {
        let sql = """
        INSERT INTO items (id, note_body, created_at, updated_at, last_seen_at)
        VALUES (?, ?, datetime('now'), datetime('now'), datetime('now'))
        ON CONFLICT(id) DO UPDATE SET
            note_body = excluded.note_body,
            updated_at = datetime('now'),
            last_seen_at = datetime('now')
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            persistenceError = databaseError("prepare save body")
            return
        }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, body, -1, SQLITE_TRANSIENT)
        if sqlite3_step(stmt) == SQLITE_DONE {
            persistenceError = nil
            version += 1
        } else {
            persistenceError = databaseError("save body")
        }
        sqlite3_finalize(stmt)
    }

    func tags(for id: String) -> [String] {
        let sql = "SELECT tags_json FROM items WHERE id = ? LIMIT 1"
        var stmt: OpaquePointer?
        var value = ""
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                value = columnString(stmt, 0)
            }
        }
        sqlite3_finalize(stmt)
        guard let data = value.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    func setTags(_ tags: [String], for id: String) {
        let tagsData = (try? JSONEncoder().encode(tags)) ?? Data()
        let tagsJSON = String(data: tagsData, encoding: .utf8) ?? "[]"
        let sql = """
        INSERT INTO items (id, tags_json, created_at, updated_at, last_seen_at)
        VALUES (?, ?, datetime('now'), datetime('now'), datetime('now'))
        ON CONFLICT(id) DO UPDATE SET
            tags_json = excluded.tags_json,
            updated_at = datetime('now'),
            last_seen_at = datetime('now')
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            persistenceError = databaseError("prepare save tags")
            return
        }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, tagsJSON, -1, SQLITE_TRANSIENT)
        if sqlite3_step(stmt) == SQLITE_DONE {
            persistenceError = nil
            version += 1
        } else {
            persistenceError = databaseError("save tags")
        }
        sqlite3_finalize(stmt)
    }

    func paperIDs(for id: String) -> [String] {
        let sql = "SELECT paper_id FROM item_papers WHERE item_id = ?"
        var stmt: OpaquePointer?
        var results: [String] = []
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(columnString(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        return results
    }

    func setPaperIDs(_ paperIDs: [String], for id: String) {
        let deleteSql = "DELETE FROM item_papers WHERE item_id = ?"
        var deleteStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSql, -1, &deleteStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(deleteStmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(deleteStmt)
        }
        sqlite3_finalize(deleteStmt)

        let insertSql = "INSERT OR IGNORE INTO item_papers (item_id, paper_id) VALUES (?, ?)"
        var insertStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSql, -1, &insertStmt, nil) == SQLITE_OK {
            for paperID in paperIDs {
                sqlite3_bind_text(insertStmt, 1, id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insertStmt, 2, paperID, -1, SQLITE_TRANSIENT)
                sqlite3_step(insertStmt)
                sqlite3_reset(insertStmt)
            }
        }
        sqlite3_finalize(insertStmt)
        version += 1
    }

    func commits(for id: String) -> [String] {
        let sql = "SELECT commit_id FROM item_commits WHERE item_id = ?"
        var stmt: OpaquePointer?
        var results: [String] = []
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(columnString(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        return results
    }

    func setCommits(_ commits: [String], for id: String) {
        let deleteSql = "DELETE FROM item_commits WHERE item_id = ?"
        var deleteStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSql, -1, &deleteStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(deleteStmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(deleteStmt)
        }
        sqlite3_finalize(deleteStmt)

        let insertSql = "INSERT OR IGNORE INTO item_commits (item_id, commit_id) VALUES (?, ?)"
        var insertStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSql, -1, &insertStmt, nil) == SQLITE_OK {
            for commit in commits {
                sqlite3_bind_text(insertStmt, 1, id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insertStmt, 2, commit, -1, SQLITE_TRANSIENT)
                sqlite3_step(insertStmt)
                sqlite3_reset(insertStmt)
            }
        }
        sqlite3_finalize(insertStmt)
        version += 1
    }

    func saveAll(id: String, body: String, tags: [String], paperIDs: [String], commits: [String]) {
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)

        let tagsData = (try? JSONEncoder().encode(tags)) ?? Data()
        let tagsJSON = String(data: tagsData, encoding: .utf8) ?? "[]"
        let sql = """
        INSERT INTO items (id, note_body, tags_json, created_at, updated_at, last_seen_at)
        VALUES (?, ?, ?, datetime('now'), datetime('now'), datetime('now'))
        ON CONFLICT(id) DO UPDATE SET
            note_body = excluded.note_body,
            tags_json = excluded.tags_json,
            updated_at = datetime('now'),
            last_seen_at = datetime('now')
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, body, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, tagsJSON, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)

        let deletePapersSql = "DELETE FROM item_papers WHERE item_id = ?"
        var deletePapersStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deletePapersSql, -1, &deletePapersStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(deletePapersStmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(deletePapersStmt)
        }
        sqlite3_finalize(deletePapersStmt)

        let insertPaperSql = "INSERT OR IGNORE INTO item_papers (item_id, paper_id) VALUES (?, ?)"
        var insertPaperStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertPaperSql, -1, &insertPaperStmt, nil) == SQLITE_OK {
            for paperID in paperIDs {
                sqlite3_bind_text(insertPaperStmt, 1, id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insertPaperStmt, 2, paperID, -1, SQLITE_TRANSIENT)
                sqlite3_step(insertPaperStmt)
                sqlite3_reset(insertPaperStmt)
            }
        }
        sqlite3_finalize(insertPaperStmt)

        let deleteCommitsSql = "DELETE FROM item_commits WHERE item_id = ?"
        var deleteCommitsStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteCommitsSql, -1, &deleteCommitsStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(deleteCommitsStmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(deleteCommitsStmt)
        }
        sqlite3_finalize(deleteCommitsStmt)

        let insertCommitSql = "INSERT OR IGNORE INTO item_commits (item_id, commit_id) VALUES (?, ?)"
        var insertCommitStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertCommitSql, -1, &insertCommitStmt, nil) == SQLITE_OK {
            for commit in commits {
                sqlite3_bind_text(insertCommitStmt, 1, id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(insertCommitStmt, 2, commit, -1, SQLITE_TRANSIENT)
                sqlite3_step(insertCommitStmt)
                sqlite3_reset(insertCommitStmt)
            }
        }
        sqlite3_finalize(insertCommitStmt)

        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        version += 1
    }

    func updateLastSeen(id: String) {
        let sql = "UPDATE items SET last_seen_at = datetime('now') WHERE id = ?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    private func openDatabase() {
        let url = dbURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            persistenceError = "Could not open database at \(url.path)"
        } else {
            sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
            sqlite3_busy_timeout(db, 5000)
            persistenceError = nil
        }
    }

    private func createTablesIfNeeded() {
        // Drop the old structure table if it exists
        _ = sqlite3_exec(db, "DROP TABLE IF EXISTS item_notes;", nil, nil, nil)

        let schema = """
        CREATE TABLE IF NOT EXISTS items (
            id TEXT PRIMARY KEY,
            note_body TEXT NOT NULL DEFAULT '',
            tags_json TEXT NOT NULL DEFAULT '[]',
            is_note INTEGER NOT NULL DEFAULT 0,
            pinned INTEGER NOT NULL DEFAULT 0,
            completed INTEGER NOT NULL DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now')),
            last_seen_at TEXT DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS item_papers (
            item_id TEXT,
            paper_id TEXT,
            PRIMARY KEY (item_id, paper_id)
        );

        CREATE TABLE IF NOT EXISTS item_commits (
            item_id TEXT,
            commit_id TEXT,
            PRIMARY KEY (item_id, commit_id)
        );

        CREATE INDEX IF NOT EXISTS idx_item_papers_item ON item_papers(item_id);
        CREATE INDEX IF NOT EXISTS idx_item_commits_item ON item_commits(item_id);
        CREATE INDEX IF NOT EXISTS idx_item_papers_paper ON item_papers(paper_id);
        CREATE INDEX IF NOT EXISTS idx_item_commits_commit ON item_commits(commit_id);
        """
        var errorMsg: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, schema, nil, nil, &errorMsg) != SQLITE_OK {
            persistenceError = errorMsg.map { String(cString: $0) } ?? "Could not create tables."
            sqlite3_free(errorMsg)
        }
        // Migrate older databases that predate these columns. Each ALTER fails
        // harmlessly with "duplicate column" once the column exists.
        _ = sqlite3_exec(db, "ALTER TABLE items ADD COLUMN is_note INTEGER NOT NULL DEFAULT 0;", nil, nil, nil)
        _ = sqlite3_exec(db, "ALTER TABLE items ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0;", nil, nil, nil)
        _ = sqlite3_exec(db, "ALTER TABLE items ADD COLUMN completed INTEGER NOT NULL DEFAULT 0;", nil, nil, nil)
    }

    private func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cString)
    }

    private func databaseError(_ action: String) -> String {
        let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown error"
        return "Could not \(action): \(message)"
    }
}
