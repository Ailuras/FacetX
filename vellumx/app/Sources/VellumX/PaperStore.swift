import Foundation
import Observation
import SQLite3

/// SQLite needs to COPY bound Swift strings: a Swift String bridges to a C
/// pointer that is only valid for the duration of the bind call, so passing
/// SQLITE_STATIC (nil) leaves SQLite with a dangling pointer by the time
/// sqlite3_step runs — it then stores empty/garbage. SQLITE_TRANSIENT tells
/// SQLite to make its own copy.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
@Observable
class PaperStore {
    var papers: [Paper] = []
    var paperVersion: Int = 0

    static let shared = PaperStore()

    private var db: OpaquePointer?
    private let databaseURLOverride: URL?

    var dbURL: URL {
        if let databaseURLOverride { return databaseURLOverride }
        return AppSettings.shared.resolvedStorageDirectory.appendingPathComponent("vellumx.db")
    }

    private init() {
        databaseURLOverride = nil
        openDatabase()
        createTablesIfNeeded()
        loadPapers()
    }

    init(databaseURL: URL) {
        databaseURLOverride = databaseURL
        openDatabase()
        createTablesIfNeeded()
        loadPapers()
    }

    private func openDatabase() {
        let url = dbURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            print("Error: Could not open database at \(url.path)")
        } else {
            print("Database opened at \(url.path)")
            // WAL lets the papers and metadata connections read/write the same
            // file concurrently; the busy timeout makes a blocked connection
            // wait-and-retry instead of failing immediately with SQLITE_BUSY.
            sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
            sqlite3_busy_timeout(db, 5000)
        }
    }

    private func closeDatabase() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    enum RelocateResult {
        case ok(URL)
        case failed(String)
    }

    @discardableResult
    func relocate(to newDir: URL, migrate: Bool) -> RelocateResult {
        let fm = FileManager.default
        let currentDb = dbURL
        let destDb = newDir.appendingPathComponent("vellumx.db")

        do {
            try fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        } catch {
            return .failed("无法创建目录：\(error.localizedDescription)")
        }

        if currentDb.standardizedFileURL != destDb.standardizedFileURL, migrate {
            // Flush all WAL frames into the main file before closing so the
            // moved database is self-contained (no pending uncommitted frames).
            sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil)
            closeDatabase()
            do {
                if fm.fileExists(atPath: destDb.path) {
                    try fm.removeItem(at: destDb)
                }
                if fm.fileExists(atPath: currentDb.path) {
                    try fm.moveItem(at: currentDb, to: destDb)
                }
                // Move WAL sidecar files (-wal, -shm) if they still exist after
                // the checkpoint. Without this, the destination DB would open with
                // a stale SHM index and lose any frames that weren't checkpointed.
                for suffix in ["-wal", "-shm"] {
                    let src = URL(fileURLWithPath: currentDb.path + suffix)
                    let dst = URL(fileURLWithPath: destDb.path + suffix)
                    guard fm.fileExists(atPath: src.path) else { continue }
                    if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                    try fm.moveItem(at: src, to: dst)
                }
                // Downloaded PDFs are materialized assets that must travel with
                // the database; move the whole pdfs/ directory alongside it.
                let srcPdfs = currentDb.deletingLastPathComponent().appendingPathComponent("pdfs")
                let dstPdfs = newDir.appendingPathComponent("pdfs")
                if fm.fileExists(atPath: srcPdfs.path) {
                    if fm.fileExists(atPath: dstPdfs.path) { try fm.removeItem(at: dstPdfs) }
                    try fm.moveItem(at: srcPdfs, to: dstPdfs)
                }
            } catch {
                openDatabase()
                return .failed("迁移失败：\(error.localizedDescription)")
            }
        } else if !migrate {
            closeDatabase()
        }

        AppSettings.shared.storageDirectory = newDir.path
        // Close any still-open handle before reopening. The migrate/switch
        // branches above already closed in their cases, but the
        // migrate-to-same-path case did not — without this, openDatabase would
        // overwrite a live connection pointer and leak it.
        closeDatabase()
        openDatabase()
        createTablesIfNeeded()
        loadPapers()
        // Repoint the metadata store at the new file too, otherwise its open
        // connection keeps writing the old database and the two diverge.
        MetadataStore.shared.reopen()
        return .ok(destDb)
    }

    private func createTablesIfNeeded() {
        let schema = """
        CREATE TABLE IF NOT EXISTS papers (
            id TEXT PRIMARY KEY,
            doi TEXT,
            title TEXT NOT NULL,
            authors TEXT,
            publication_date TEXT,
            venue TEXT,
            cited_by_count INTEGER DEFAULT 0,
            abstract TEXT,
            landing_page_url TEXT,
            added_at TEXT DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS paper_cache (
            paper_id TEXT PRIMARY KEY,
            venue_abbr TEXT NOT NULL DEFAULT 'Others',
            score REAL NOT NULL DEFAULT 0,
            tier INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS paper_states (
            paper_id TEXT PRIMARY KEY,
            status TEXT NOT NULL DEFAULT 'pending',
            status_changed_at TEXT DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS paper_recommendations (
            paper_id TEXT PRIMARY KEY,
            recommended_at TEXT,
            is_active INTEGER NOT NULL DEFAULT 1,
            recommendation_reason TEXT
        );

        CREATE TABLE IF NOT EXISTS paper_notes (
            paper_id TEXT PRIMARY KEY,
            note TEXT NOT NULL DEFAULT ''
        );

        CREATE TABLE IF NOT EXISTS paper_tags (
            paper_id TEXT NOT NULL,
            tag TEXT NOT NULL,
            PRIMARY KEY (paper_id, tag)
        );

        CREATE TABLE IF NOT EXISTS paper_translations (
            paper_id TEXT PRIMARY KEY,
            abstract_zh TEXT
        );

        CREATE TABLE IF NOT EXISTS paper_pdfs (
            paper_id TEXT PRIMARY KEY,
            pdf_url TEXT NOT NULL,
            pdf_source TEXT,
            pdf_path TEXT,
            pdf_status TEXT,
            byte_size INTEGER,
            sha256 TEXT,
            checked_at INTEGER,
            fetched_at INTEGER
        );

        CREATE TABLE IF NOT EXISTS paper_topics (
            paper_id TEXT NOT NULL,
            topic_name TEXT NOT NULL,
            PRIMARY KEY (paper_id, topic_name)
        );

        CREATE TABLE IF NOT EXISTS collections (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            color TEXT,
            icon TEXT,
            parent_id TEXT,
            notes TEXT
        );

        CREATE TABLE IF NOT EXISTS collection_papers (
            collection_id TEXT NOT NULL,
            paper_id TEXT NOT NULL,
            added_at TEXT DEFAULT (datetime('now')),
            PRIMARY KEY (collection_id, paper_id)
        );
        """

        var errorMsg: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, schema, nil, nil, &errorMsg) != SQLITE_OK {
            let error = errorMsg.map { String(cString: $0) } ?? "unknown error"
            print("Error creating tables: \(error)")
            sqlite3_free(errorMsg)
        }

        migratePdfSchema()
        migrateCollectionsSchema()
    }

    /// Adds the local-asset columns to `paper_pdfs` on databases created before
    /// PDFs were stored locally. `CREATE TABLE IF NOT EXISTS` leaves existing
    /// tables untouched, so new columns must be ALTERed in. Purely additive.
    private func migratePdfSchema() {
        var existing = Set<String>()
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(paper_pdfs)", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                existing.insert(columnString(stmt, 1)) // column 1 = name
            }
        }
        sqlite3_finalize(stmt)

        let columns: [(String, String)] = [
            ("pdf_path", "TEXT"),
            ("pdf_status", "TEXT"),
            ("byte_size", "INTEGER"),
            ("sha256", "TEXT"),
            ("checked_at", "INTEGER"),
            ("fetched_at", "INTEGER")
        ]
        for (name, type) in columns where !existing.contains(name) {
            sqlite3_exec(db, "ALTER TABLE paper_pdfs ADD COLUMN \(name) \(type)", nil, nil, nil)
        }
    }

    /// Adds the `notes` column to `collections` on databases created before it
    /// was introduced. `ALTER TABLE ADD COLUMN` is purely additive and safe to
    /// run multiple times — SQLite returns an error (ignored here) if the column
    /// already exists.
    private func migrateCollectionsSchema() {
        sqlite3_exec(db, "ALTER TABLE collections ADD COLUMN notes TEXT", nil, nil, nil)
    }

    func loadPapers() {
        let query = """
         SELECT p.id, p.doi, p.title, p.authors, p.publication_date, p.venue,
                COALESCE(pc.venue_abbr, 'Others') as venue_abbr,
                p.cited_by_count, p.abstract, p.landing_page_url, f.pdf_url,
                COALESCE(NULLIF((
                    SELECT group_concat(topic_name, ', ')
                    FROM (
                        SELECT topic_name
                        FROM paper_topics
                        WHERE paper_id = p.id
                            ORDER BY topic_name
                    )
                ), ''), '') as track,
                COALESCE(pc.score, 0) as score, COALESCE(pc.tier, 0) as tier,
                COALESCE(ps.status, 'pending') as status,
                COALESCE(pr.is_active, 0) as is_recommended,
                pr.recommended_at,
                COALESCE(pr.recommendation_reason, '') as recommendation_reason,
                COALESCE(NULLIF((
                    SELECT group_concat(tag, ', ')
                    FROM (
                        SELECT tag
                        FROM paper_tags
                        WHERE paper_id = p.id
                        ORDER BY lower(tag), tag
                    )
                 ), ''), '') as tags,
                COALESCE(NULLIF((
                    SELECT group_concat(collection_id, ', ')
                    FROM (
                        SELECT cp2.collection_id
                        FROM collection_papers cp2
                        WHERE cp2.paper_id = p.id
                        ORDER BY cp2.added_at, cp2.collection_id
                    )
                ), ''), '') as collections,
                 COALESCE(pn.note, '') as note, COALESCE(pt.abstract_zh, '') as abstract_zh,
                ps.status_changed_at, p.added_at,
                f.pdf_path, f.pdf_status
         FROM papers p
        LEFT JOIN paper_cache pc ON p.id = pc.paper_id
        LEFT JOIN paper_states ps ON p.id = ps.paper_id
        LEFT JOIN paper_recommendations pr ON p.id = pr.paper_id
        LEFT JOIN paper_notes pn ON p.id = pn.paper_id
        LEFT JOIN paper_translations pt ON p.id = pt.paper_id
        LEFT JOIN paper_pdfs f ON p.id = f.paper_id
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) != SQLITE_OK {
            print("Failed to prepare statement for loading papers")
            return
        }
        defer {
            sqlite3_finalize(stmt)
        }

        var loadedPapers: [Paper] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = columnString(stmt, 0)
            let doi = columnOptionalString(stmt, 1)
            let title = columnString(stmt, 2)

            var authors: [String] = []
            if let authorsRaw = sqlite3_column_text(stmt, 3) {
                let authorsStr = String(cString: authorsRaw)
                if let data = authorsStr.data(using: .utf8) {
                    authors = (try? JSONDecoder().decode([String].self, from: data)) ?? []
                }
            }

            let pubDate = columnString(stmt, 4)
            let venue = columnString(stmt, 5)
            let venueAbbr = columnString(stmt, 6)
            let citedCount = Int(sqlite3_column_int(stmt, 7))
            let abstract = columnString(stmt, 8)
            let landingPage = columnString(stmt, 9)
            let pdfUrl = columnOptionalString(stmt, 10)
            let track = columnString(stmt, 11)
            let score = sqlite3_column_double(stmt, 12)

            let tier = Int(sqlite3_column_int(stmt, 13))

            let statusRaw = columnString(stmt, 14)
            let status = PaperStatus(rawValue: statusRaw) ?? .pending
            let isRecommended = sqlite3_column_int(stmt, 15) == 1
            let recommendedAtRaw = columnOptionalString(stmt, 16)
            let recommendedAt = recommendedAtRaw.flatMap(Self.parseSQLiteDate)
            let recommendationReason = columnString(stmt, 17)
            let tags = Self.splitCSV(columnString(stmt, 18))
            let collectionIds = Self.splitCSV(columnString(stmt, 19))
            let note = columnString(stmt, 20)
            let abstractZh = columnString(stmt, 21)
            let statusChangedAt = columnOptionalString(stmt, 22).flatMap(Self.parseSQLiteDate)
            let addedAt = columnOptionalString(stmt, 23).flatMap(Self.parseSQLiteDate)
            let pdfLocalPath = columnOptionalString(stmt, 24)
            let pdfStatus = columnOptionalString(stmt, 25)

            var pubYear: Int? = nil
            if pubDate.count >= 4 {
                pubYear = Int(pubDate.prefix(4))
            }

            let paper = Paper(
                id: id,
                doi: doi,
                title: title,
                authors: authors,
                publicationDate: pubDate,
                publicationYear: pubYear,
                venue: venue,
                venueAbbr: venueAbbr,
                citedByCount: citedCount,
                abstract: abstract,
                landingPageUrl: landingPage,
                pdfUrl: pdfUrl,
                pdfLocalPath: pdfLocalPath,
                pdfStatus: pdfStatus,
                track: track,
                score: score,
                tier: tier,
                status: status,
                isRecommended: isRecommended,
                recommendedAt: recommendedAt,
                recommendationReason: recommendationReason,
                tags: tags,
                collectionIds: collectionIds,
                note: note,
                abstractZh: abstractZh,
                statusChangedAt: statusChangedAt,
                addedAt: addedAt
            )
            loadedPapers.append(paper)
        }

        self.papers = loadedPapers
        paperVersion += 1
    }

    func addOrUpdate(papers newPapers: [Paper]) -> (inserted: Int, updated: Int) {
        var inserted = 0
        var updated = 0

        sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil)
        for paper in newPapers {
            let paperId = existingPaperId(for: paper) ?? paper.id
            var authorsJson = ""
            if let authorsData = try? JSONEncoder().encode(paper.authors) {
                authorsJson = String(data: authorsData, encoding: .utf8) ?? "[]"
            }

            if paperId == paper.id, existingPaperId(matchingId: paper.id) == nil {
                if insertPaper(paper, authorsJson: authorsJson) {
                    inserted += 1
                    upsertPaperCache(paperId: paper.id, paper: paper)
                    replaceTopics(for: paper.id, track: paper.track)
                    upsertPaperPdfCache(paperId: paper.id, paper: paper)
                    insertPendingStateIfNeeded(paperId: paper.id)
                }
            } else if updatePaper(id: paperId, with: paper, authorsJson: authorsJson) {
                updated += 1
                upsertPaperCache(paperId: paperId, paper: paper)
                replaceTopics(for: paperId, track: paper.track)
                upsertPaperPdfCache(paperId: paperId, paper: paper)
            }
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)

        loadPapers()
        return (inserted, updated)
    }

    private func existingPaperId(for paper: Paper) -> String? {
        if let id = existingPaperId(matchingId: paper.id) {
            return id
        }
        guard let doi = paper.doi?.trimmingCharacters(in: .whitespacesAndNewlines), !doi.isEmpty else {
            return nil
        }
        return existingPaperId(matchingDoi: doi)
    }

    private func existingPaperId(matchingId id: String) -> String? {
        queryPaperId(sql: "SELECT id FROM papers WHERE id = ? LIMIT 1", value: id)
    }

    private func existingPaperId(matchingDoi doi: String) -> String? {
        queryPaperId(sql: "SELECT id FROM papers WHERE doi = ? LIMIT 1", value: doi)
    }

    private func queryPaperId(sql: String, value: String) -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, value, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW, let raw = sqlite3_column_text(stmt, 0) else {
            return nil
        }
        return String(cString: raw)
    }

    private func updatePaper(id: String, with paper: Paper, authorsJson: String) -> Bool {
        let sql = """
        UPDATE papers SET
            doi = ?, title = ?, authors = ?, publication_date = ?, venue = ?,
            cited_by_count = ?, abstract = ?, landing_page_url = ?
        WHERE id = ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, paper.doi, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, paper.title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, authorsJson, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, paper.publicationDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, paper.venue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 6, Int32(paper.citedByCount))
        sqlite3_bind_text(stmt, 7, paper.abstract, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 8, paper.landingPageUrl, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 9, id, -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_DONE && sqlite3_changes(db) > 0
    }

    private func insertPaper(_ paper: Paper, authorsJson: String) -> Bool {
        let sql = """
        INSERT INTO papers (
            id, doi, title, authors, publication_date, venue,
            cited_by_count, abstract, landing_page_url
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, paper.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, paper.doi, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, paper.title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, authorsJson, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, paper.publicationDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, paper.venue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 7, Int32(paper.citedByCount))
        sqlite3_bind_text(stmt, 8, paper.abstract, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 9, paper.landingPageUrl, -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    private func insertPendingStateIfNeeded(paperId: String) {
        let sql = "INSERT OR IGNORE INTO paper_states (paper_id, status) VALUES (?, 'pending')"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, paperId, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    func refreshVenueMetadata() -> Int {
        let scorer = VenueScorer(
            config: ConfigManager.shared.effectiveConfig,
            venues: MetadataStore.shared.venues
        )
        let updateSql = """
        INSERT INTO paper_cache (paper_id, venue_abbr, score, tier)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(paper_id) DO UPDATE SET
            venue_abbr = excluded.venue_abbr,
            score = excluded.score,
            tier = excluded.tier
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, updateSql, -1, &stmt, nil) != SQLITE_OK {
            print("Failed to prepare venue metadata refresh")
            return 0
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil)
        var changed = 0

        for paper in papers {
            let (tier, venueAbbr, score) = scorer.evaluate(venue: paper.venue, citations: paper.citedByCount)

            guard venueAbbr != paper.venueAbbr || tier != paper.tier || abs(score - paper.score) > 0.0001 else {
                continue
            }

            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, paper.id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, venueAbbr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 3, score)
            sqlite3_bind_int(stmt, 4, Int32(tier))

            if sqlite3_step(stmt) == SQLITE_DONE {
                changed += 1
            }
        }

        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        loadPapers()
        return changed
    }

    private func replaceTopics(for paperId: String, track: String) {
        let topics = Self.splitCSV(track)

        let deleteSql = "DELETE FROM paper_topics WHERE paper_id = ?"
        var deleteStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSql, -1, &deleteStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(deleteStmt, 1, paperId, -1, SQLITE_TRANSIENT)
            sqlite3_step(deleteStmt)
            sqlite3_finalize(deleteStmt)
        }

        insertTopics(for: paperId, topics: topics)
    }

    private func upsertPaperCache(paperId: String, paper: Paper) {
        let sql = """
        INSERT INTO paper_cache (paper_id, venue_abbr, score, tier)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(paper_id) DO UPDATE SET
            venue_abbr = excluded.venue_abbr,
            score = excluded.score,
            tier = excluded.tier
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, paperId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, paper.venueAbbr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 3, paper.score)
        sqlite3_bind_int(stmt, 4, Int32(paper.tier))
        sqlite3_step(stmt)
    }

    private func upsertPaperPdfCache(paperId: String, paper: Paper) {
        guard let pdfUrl = paper.pdfUrl, !pdfUrl.isEmpty else { return }
        let sql = """
        INSERT INTO paper_pdfs (paper_id, pdf_url, pdf_source)
        VALUES (?, ?, 'OpenAlex')
        ON CONFLICT(paper_id) DO NOTHING
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, paperId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, pdfUrl, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    private func insertTopics(for paperId: String, topics: [String]) {
        let insertSql = "INSERT OR IGNORE INTO paper_topics (paper_id, topic_name) VALUES (?, ?)"
        var insertStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSql, -1, &insertStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(insertStmt) }

        for topic in topics {
            sqlite3_reset(insertStmt)
            sqlite3_clear_bindings(insertStmt)
            sqlite3_bind_text(insertStmt, 1, paperId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(insertStmt, 2, topic, -1, SQLITE_TRANSIENT)
            sqlite3_step(insertStmt)
        }
    }

    /// Split a comma-separated SQLite string into trimmed, non-empty tokens.
    /// Used for topics, tags, and collection IDs stored as group_concat results.
    static func splitCSV(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func normalizedTag(_ value: String) -> String? {
        var tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while tag.hasPrefix("#") {
            tag.removeFirst()
            tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return tag.isEmpty ? nil : tag
    }

    static let sqliteDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func parseSQLiteDate(_ value: String) -> Date? {
        sqliteDateFormatter.date(from: value)
    }

    private func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        sqlite3_column_text(stmt, index).map { String(cString: $0) } ?? ""
    }

    private func columnOptionalString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let raw = sqlite3_column_text(stmt, index) else { return nil }
        let value = String(cString: raw)
        return value.isEmpty ? nil : value
    }

    func setPaperStatus(id: String, status: PaperStatus) {
        let sql = """
        INSERT INTO paper_states (paper_id, status, status_changed_at)
        VALUES (?, ?, datetime('now'))
        ON CONFLICT(paper_id) DO UPDATE SET
            status = excluded.status,
            status_changed_at = datetime('now')
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, status.rawValue, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_DONE {
                if let idx = papers.firstIndex(where: { $0.id == id }) {
                    papers[idx].status = status
                }
                paperVersion += 1
            }
            sqlite3_finalize(stmt)
        }
    }

    func setPaperRecommended(id: String, isRecommended: Bool, reason: String = "") {
        let sql: String
        if isRecommended {
            sql = """
            INSERT INTO paper_recommendations (paper_id, recommended_at, is_active, recommendation_reason)
            VALUES (?, datetime('now'), 1, ?)
            ON CONFLICT(paper_id) DO UPDATE SET
                recommended_at = datetime('now'),
                is_active = 1,
                recommendation_reason = excluded.recommendation_reason
            """
        } else {
            sql = """
            INSERT INTO paper_recommendations (paper_id, recommended_at, is_active, recommendation_reason)
            VALUES (?, NULL, 0, '')
            ON CONFLICT(paper_id) DO UPDATE SET
                recommended_at = NULL,
                is_active = 0,
                recommendation_reason = ''
            """
        }

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            if isRecommended {
                sqlite3_bind_text(stmt, 2, reason, -1, SQLITE_TRANSIENT)
            }
            if sqlite3_step(stmt) == SQLITE_DONE {
                if let idx = papers.firstIndex(where: { $0.id == id }) {
                    papers[idx].isRecommended = isRecommended
                    if isRecommended {
                        papers[idx].recommendedAt = Date()
                        papers[idx].recommendationReason = reason
                    } else {
                        papers[idx].recommendedAt = nil
                        papers[idx].recommendationReason = ""
                    }
                }
                paperVersion += 1
            }
            sqlite3_finalize(stmt)
        }
    }

    func setPaperNote(id: String, note: String) {
        let sql = """
        INSERT INTO paper_notes (paper_id, note)
        VALUES (?, ?)
        ON CONFLICT(paper_id) DO UPDATE SET
            note = excluded.note
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, note, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_DONE {
                if let idx = papers.firstIndex(where: { $0.id == id }) {
                    papers[idx].note = note
                }
                paperVersion += 1
            }
            sqlite3_finalize(stmt)
        }
    }

    var allTags: [String] {
        Array(Set(papers.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func addPaperTag(id: String, tag rawTag: String) {
        guard let tag = Self.normalizedTag(rawTag) else { return }
        let sql = "INSERT OR IGNORE INTO paper_tags (paper_id, tag) VALUES (?, ?)"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, tag, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_DONE {
                if let idx = papers.firstIndex(where: { $0.id == id }), !papers[idx].tags.contains(tag) {
                    papers[idx].tags.append(tag)
                    papers[idx].tags.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                }
                paperVersion += 1
            }
            sqlite3_finalize(stmt)
        }
    }

    func removePaperTag(id: String, tag rawTag: String) {
        guard let tag = Self.normalizedTag(rawTag) else { return }
        let sql = "DELETE FROM paper_tags WHERE paper_id = ? AND tag = ?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, tag, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_DONE {
                if let idx = papers.firstIndex(where: { $0.id == id }) {
                    papers[idx].tags.removeAll { $0 == tag }
                }
                paperVersion += 1
            }
            sqlite3_finalize(stmt)
        }
    }

    func setPaperTranslation(id: String, abstractZh: String) {
        let sql = """
        INSERT INTO paper_translations (paper_id, abstract_zh)
        VALUES (?, ?)
        ON CONFLICT(paper_id) DO UPDATE SET
            abstract_zh = excluded.abstract_zh
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, abstractZh, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_DONE {
                if let idx = papers.firstIndex(where: { $0.id == id }) {
                    papers[idx].abstractZh = abstractZh
                }
                paperVersion += 1
            }
            sqlite3_finalize(stmt)
        }
    }

    /// Persists the outcome of a PDF fetch (see `PdfFetcher`). A `.downloaded`
    /// or `.notPdf` result always carries a URL and upserts the full row; a
    /// `.dead` result (no link found) only stamps the status onto an existing
    /// row, leaving any previously known URL intact.
    func savePdf(id: String, result: PdfFetchResult) {
        let now = Int(Date().timeIntervalSince1970)

        if result.status == .dead {
            let sql = """
            UPDATE paper_pdfs SET pdf_source = NULL, pdf_path = NULL, byte_size = NULL,
                                  sha256 = NULL, pdf_status = ?, checked_at = ? WHERE paper_id = ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, result.status.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, Int64(now))
            sqlite3_bind_text(stmt, 3, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            applyPdfResultInMemory(id: id, result: result)
            return
        }

        let sql = """
        INSERT INTO paper_pdfs
            (paper_id, pdf_url, pdf_source, pdf_path, pdf_status, byte_size, sha256, checked_at, fetched_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(paper_id) DO UPDATE SET
            pdf_url = excluded.pdf_url,
            pdf_source = excluded.pdf_source,
            pdf_path = excluded.pdf_path,
            pdf_status = excluded.pdf_status,
            byte_size = excluded.byte_size,
            sha256 = excluded.sha256,
            checked_at = excluded.checked_at,
            fetched_at = excluded.fetched_at
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, result.url ?? "", -1, SQLITE_TRANSIENT)
        bindOptionalText(stmt, 3, result.source)
        bindOptionalText(stmt, 4, result.localPath)
        sqlite3_bind_text(stmt, 5, result.status.rawValue, -1, SQLITE_TRANSIENT)
        if let size = result.byteSize { sqlite3_bind_int64(stmt, 6, Int64(size)) } else { sqlite3_bind_null(stmt, 6) }
        bindOptionalText(stmt, 7, result.sha256)
        sqlite3_bind_int64(stmt, 8, Int64(now))
        if result.status == .downloaded { sqlite3_bind_int64(stmt, 9, Int64(now)) } else { sqlite3_bind_null(stmt, 9) }

        if sqlite3_step(stmt) == SQLITE_DONE {
            applyPdfResultInMemory(id: id, result: result)
        }
    }

    /// Removes a paper's PDF record (used by manual "Remove PDF"). The caller is
    /// responsible for deleting the file on disk via `PdfStorage`.
    func removePdf(id: String) {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM paper_pdfs WHERE paper_id = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)

        if let idx = papers.firstIndex(where: { $0.id == id }) {
            let paper = papers[idx]
            paper.pdfUrl = nil
            paper.pdfLocalPath = nil
            paper.pdfStatus = nil
            papers[idx] = paper
            paperVersion += 1
        }
    }

    private func applyPdfResultInMemory(id: String, result: PdfFetchResult) {
        guard let idx = papers.firstIndex(where: { $0.id == id }) else { return }
        let paper = papers[idx]
        if let url = result.url { paper.pdfUrl = url }
        paper.pdfLocalPath = result.localPath
        paper.pdfStatus = result.status.rawValue
        // `Paper` is a reference type, so mutating its fields does not notify the
        // @Observable store. Reassign the element through the array subscript so
        // observers of `papers` (e.g. the detail view's icon) re-render.
        papers[idx] = paper
        paperVersion += 1
    }

    // MARK: - Collections

    var allCollections: [PaperCollection] {
        let sql = "SELECT id, name, color, icon, parent_id FROM collections ORDER BY lower(name), name"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var rows: [PaperCollection] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = columnString(stmt, 0)
            let name = columnString(stmt, 1)
            let color = columnOptionalString(stmt, 2)
            let icon = columnOptionalString(stmt, 3)
            let parentId = columnOptionalString(stmt, 4)
            rows.append(PaperCollection(id: id, name: name, color: color, icon: icon, parentId: parentId))
        }
        return rows
    }

    @discardableResult
    func createCollection(name: String, color: String? = nil,
                          icon: String? = nil, parentId: String? = nil) -> PaperCollection? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let id = UUID().uuidString
        let sql = "INSERT INTO collections (id, name, color, icon, parent_id) VALUES (?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, trimmedName, -1, SQLITE_TRANSIENT)
        bindOptionalText(stmt, 3, color)
        bindOptionalText(stmt, 4, icon)
        bindOptionalText(stmt, 5, parentId)
        guard sqlite3_step(stmt) == SQLITE_DONE else { return nil }
        paperVersion += 1
        return PaperCollection(id: id, name: trimmedName, color: color, icon: icon, parentId: parentId)
    }

    func renameCollection(id: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateCollectionColumn(id: id, column: "name", value: trimmed)
    }

    func setCollectionIcon(id: String, icon: String?) {
        updateCollectionColumn(id: id, column: "icon", value: icon)
    }

    func setCollectionColor(id: String, color: String?) {
        updateCollectionColumn(id: id, column: "color", value: color)
    }

    private func updateCollectionColumn(id: String, column: String, value: String?) {
        // `column` is a fixed internal literal, never user input — safe to interpolate.
        let sql = "UPDATE collections SET \(column) = ? WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindOptionalText(stmt, 1, value)
        sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT)
        if sqlite3_step(stmt) == SQLITE_DONE { paperVersion += 1 }
    }

    /// Returns `id` plus every descendant collection id (recursive), so a parent
    /// folder can stand in for its whole subtree when filtering or deleting.
    func collectionSubtreeIds(_ id: String) -> Set<String> {
        let sql = """
        WITH RECURSIVE sub(id) AS (
            SELECT id FROM collections WHERE id = ?1
            UNION ALL
            SELECT c.id FROM collections c JOIN sub ON c.parent_id = sub.id
        )
        SELECT id FROM sub
        """
        var stmt: OpaquePointer?
        var ids = Set<String>()
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                ids.insert(columnString(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        return ids
    }

    /// Deletes a collection together with its whole subtree, dropping the
    /// papers' memberships in those collections too (no orphaned rows left).
    func deleteCollection(id: String) { deleteCollections(ids: [id]) }

    /// Deletes several collections and their subtrees in one transaction with a
    /// single reload — the batch form behind multi-select delete.
    func deleteCollections(ids: [String]) {
        guard !ids.isEmpty else { return }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let purge = """
        WITH RECURSIVE sub(id) AS (
            SELECT id FROM collections WHERE id IN (\(placeholders))
            UNION ALL
            SELECT c.id FROM collections c JOIN sub ON c.parent_id = sub.id
        )
        DELETE FROM %TABLE% WHERE %COL% IN (SELECT id FROM sub)
        """
        sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil)
        var succeeded = true
        for (table, col) in [("collection_papers", "collection_id"), ("collections", "id")] {
            let sql = purge.replacingOccurrences(of: "%TABLE%", with: table)
                           .replacingOccurrences(of: "%COL%", with: col)
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                succeeded = false
                break
            }
            for (offset, id) in ids.enumerated() {
                sqlite3_bind_text(stmt, Int32(offset + 1), id, -1, SQLITE_TRANSIENT)
            }
            if sqlite3_step(stmt) != SQLITE_DONE { succeeded = false }
            sqlite3_finalize(stmt)
        }
        sqlite3_exec(db, succeeded ? "COMMIT" : "ROLLBACK", nil, nil, nil)
        if succeeded { loadPapers() }
    }

    /// Removes every paper from a collection and its subfolders, leaving the
    /// collections themselves (and the papers in the library) intact. Clears the
    /// whole subtree so the emptied folder matches what selecting it shows — its
    /// descendants' papers no longer surface under it either.
    func clearCollection(id: String) { clearCollections(ids: [id]) }

    /// Empties several collections (and their subtrees) in one statement — the
    /// batch form behind multi-select clear.
    func clearCollections(ids: [String]) {
        guard !ids.isEmpty else { return }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let purge = """
        WITH RECURSIVE sub(id) AS (
            SELECT id FROM collections WHERE id IN (\(placeholders))
            UNION ALL
            SELECT c.id FROM collections c JOIN sub ON c.parent_id = sub.id
        )
        DELETE FROM collection_papers WHERE collection_id IN (SELECT id FROM sub)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, purge, -1, &stmt, nil) == SQLITE_OK else { return }
        for (offset, id) in ids.enumerated() {
            sqlite3_bind_text(stmt, Int32(offset + 1), id, -1, SQLITE_TRANSIENT)
        }
        let ok = sqlite3_step(stmt) == SQLITE_DONE
        sqlite3_finalize(stmt)
        if ok { loadPapers() }
    }

    /// Permanently delete one or more papers and every associated row (cache,
    /// state, recommendation, note, tags, translation, pdf, topics, collection
    /// links) in a single transaction, with one reload at the end.
    func deletePapers(ids: [String]) {
        guard !ids.isEmpty else { return }
        let tables: [(table: String, column: String)] = [
            ("collection_papers", "paper_id"),
            ("paper_topics", "paper_id"),
            ("paper_pdfs", "paper_id"),
            ("paper_translations", "paper_id"),
            ("paper_tags", "paper_id"),
            ("paper_notes", "paper_id"),
            ("paper_recommendations", "paper_id"),
            ("paper_states", "paper_id"),
            ("paper_cache", "paper_id"),
            ("papers", "id"),
        ]
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil)
        var succeeded = true
        for (table, column) in tables {
            let sql = "DELETE FROM \(table) WHERE \(column) IN (\(placeholders))"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                succeeded = false
                break
            }
            for (offset, id) in ids.enumerated() {
                sqlite3_bind_text(stmt, Int32(offset + 1), id, -1, SQLITE_TRANSIENT)
            }
            if sqlite3_step(stmt) != SQLITE_DONE { succeeded = false }
            sqlite3_finalize(stmt)
            if !succeeded { break }
        }
        sqlite3_exec(db, succeeded ? "COMMIT" : "ROLLBACK", nil, nil, nil)
        if succeeded { loadPapers() }
    }

    /// Paper ids whose *only* topic is `topicName`. Deleting the topic removes
    /// these papers entirely; papers also tagged with other topics are kept.
    /// Drives the delete confirmation count.
    func paperIdsSolelyInTopic(_ topicName: String) -> [String] {
        let sql = """
        SELECT paper_id FROM paper_topics WHERE topic_name = ?1
          AND paper_id NOT IN (SELECT paper_id FROM paper_topics WHERE topic_name <> ?1)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, topicName, -1, SQLITE_TRANSIENT)
        var ids: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) { ids.append(String(cString: c)) }
        }
        return ids
    }

    /// Remove `topicName` from the library: papers belonging only to it are
    /// deleted; papers also tagged with other topics keep those and just lose
    /// this one. Pair with `MetadataStore.deleteTopic` to drop the topic itself.
    func purgeTopicPapers(_ topicName: String) {
        let sole = paperIdsSolelyInTopic(topicName)
        if !sole.isEmpty { deletePapers(ids: sole) }
        let sql = "DELETE FROM paper_topics WHERE topic_name = ?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, topicName, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        loadPapers()
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    func addPaperToCollection(paperId: String, collectionId: String) {
        let sql = "INSERT OR IGNORE INTO collection_papers (collection_id, paper_id) VALUES (?, ?)"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, collectionId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, paperId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_DONE {
                if let idx = papers.firstIndex(where: { $0.id == paperId }),
                   !papers[idx].collectionIds.contains(collectionId) {
                    papers[idx].collectionIds.append(collectionId)
                    papers[idx].collectionIds.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                }
                paperVersion += 1
            }
            sqlite3_finalize(stmt)
        }
    }

    func removePaperFromCollection(paperId: String, collectionId: String) {
        let sql = "DELETE FROM collection_papers WHERE collection_id = ? AND paper_id = ?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, collectionId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, paperId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_DONE {
                if let idx = papers.firstIndex(where: { $0.id == paperId }) {
                    papers[idx].collectionIds.removeAll { $0 == collectionId }
                }
                paperVersion += 1
            }
            sqlite3_finalize(stmt)
        }
    }
}
