import Foundation
import Observation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
@Observable
final class ItemNoteStore {
    static let shared = ItemNoteStore()

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

    func body(for id: String) -> String {
        let sql = "SELECT body FROM item_notes WHERE id = ? LIMIT 1"
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
        INSERT INTO item_notes (id, body, created_at, updated_at)
        VALUES (?, ?, datetime('now'), datetime('now'))
        ON CONFLICT(id) DO UPDATE SET
            body = excluded.body,
            updated_at = datetime('now')
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            persistenceError = databaseError("prepare save")
            return
        }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, body, -1, SQLITE_TRANSIENT)
        if sqlite3_step(stmt) == SQLITE_DONE {
            persistenceError = nil
            version += 1
        } else {
            persistenceError = databaseError("save")
        }
        sqlite3_finalize(stmt)
    }

    private func openDatabase() {
        let url = dbURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            persistenceError = "Could not open item notes database at \(url.path)"
        } else {
            sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
            sqlite3_busy_timeout(db, 5000)
            persistenceError = nil
        }
    }

    private func createTablesIfNeeded() {
        let sql = """
        CREATE TABLE IF NOT EXISTS item_notes (
            id TEXT PRIMARY KEY,
            body TEXT NOT NULL DEFAULT '',
            created_at TEXT DEFAULT (datetime('now')),
            updated_at TEXT DEFAULT (datetime('now'))
        );
        """
        var errorMsg: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &errorMsg) != SQLITE_OK {
            persistenceError = errorMsg.map { String(cString: $0) } ?? "Could not create item notes table."
            sqlite3_free(errorMsg)
        }
    }

    private func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cString)
    }

    private func databaseError(_ action: String) -> String {
        let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown error"
        return "Could not \(action) item note: \(message)"
    }
}
