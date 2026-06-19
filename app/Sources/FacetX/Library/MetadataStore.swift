import Foundation
import Observation
import SQLite3
import SwiftUI

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct FieldPref: Identifiable, Equatable {
    var id: String
    var name: String
    var color: String?
    var sortOrder: Int
}

struct TierPref: Identifiable, Equatable {
    var id: Int { rank }
    var rank: Int
    var name: String
    var points: Int
    var color: String?
    var sortOrder: Int
}

@MainActor
@Observable
final class MetadataStore {
    static let shared = MetadataStore()

    var topics: [TrackPref] = [] { didSet { persistIfReady(saveTopics) } }
    var fields: [FieldPref] = [] { didSet { persistIfReady(saveFields) } }
    var tiers: [TierPref] = [] { didSet { persistScoringRule(saveTiers) } }
    var venues: [VenuePref] = [] { didSet { persistScoringRule(saveVenues) } }
    var citationBreakpoints: [CitationBreakpoint] = [] { didSet { persistScoringRule(saveScoring) } }
    var maxCitationPoints: Int = 0 { didSet { persistScoringRule(saveScoring) } }
    /// Tier given to papers whose venue matches no rule (the fixed "Others"
    /// fallback row). 0 = unranked.
    var othersTier: Int = 0 { didSet { persistScoringRule(saveScoring) } }
    var metadataVersion: Int = 0
    var rulesDirty = false

    private var db: OpaquePointer?
    private var isLoading = false

    private init() {
        openDatabase()
        createTablesIfNeeded()
        seedDefaultsIfNeeded()
        load()
    }

    var allFields: [String] {
        let names = fields.compactMap { Self.normalizedFieldName($0.name) }.filter { $0 != Self.othersField }
        return Array(Set(names)).sorted() + [Self.othersField]
    }

    var allTiers: [Int] {
        let ranks = Set(tiers.map(\.rank) + venues.map(\.tier))
        return Array(ranks).sorted()
    }

    func field(forAbbr abbr: String) -> String {
        guard let venue = venues.first(where: { $0.abbr.caseInsensitiveCompare(abbr) == .orderedSame }) else {
            return Self.othersField
        }
        return Self.normalizedField(venue.field) ?? Self.othersField
    }

    func topicColor(_ topic: String) -> Color {
        color(named: topics.first(where: { $0.name == topic })?.color, default: .purple)
    }

    func visibleTopicNames(in track: String) -> [String] {
        let archived = Set(topics.filter { $0.archived }.map(\.name))
        return track.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !archived.contains($0) }
    }

    func fieldColor(_ field: String?) -> Color {
        let normalized = Self.normalizedField(field) ?? Self.othersField
        if normalized == Self.othersField {
            return color(named: fields.first(where: { $0.name == normalized })?.color, default: .gray)
        }
        return color(named: fields.first(where: { $0.name == normalized })?.color, default: .teal)
    }

    func tierColor(_ tier: Int) -> Color {
        color(named: tiers.first(where: { $0.rank == tier })?.color, default: Self.tierDefaultColor(tier))
    }

    func color(forKey key: String, default defaultColor: LabelColor) -> Color {
        if let colorName = colorName(forKey: key) {
            return LabelColor.color(named: colorName) ?? defaultColor.color
        }
        return defaultColor.color
    }

    func setLabelColor(key: String, colorName: String?) {
        if key.hasPrefix("field:") {
            guard let name = Self.normalizedFieldName(String(key.dropFirst("field:".count))) else { return }
            if let index = fields.firstIndex(where: { $0.name == name }) {
                fields[index].color = colorName
            } else {
                fields.append(FieldPref(id: UUID().uuidString, name: name, color: colorName, sortOrder: fields.count))
            }
        } else if key.hasPrefix("tier:"), let rank = Int(key.dropFirst("tier:".count)) {
            if let index = tiers.firstIndex(where: { $0.rank == rank }) {
                tiers[index].color = colorName
            } else {
                tiers.append(TierPref(rank: rank, name: "Tier \(rank)", points: Self.defaultPoints(for: rank), color: colorName, sortOrder: tiers.count))
            }
        }
        metadataVersion += 1
    }

    func addField() {
        var next = 1
        var name = "Field \(next)"
        let existing = Set(fields.compactMap { Self.normalizedFieldName($0.name) })
        while existing.contains(name) {
            next += 1
            name = "Field \(next)"
        }
        fields.append(FieldPref(id: UUID().uuidString, name: name, color: "teal", sortOrder: fields.count))
        metadataVersion += 1
    }

    func renameField(id: String, to rawName: String) {
        guard let index = fields.firstIndex(where: { $0.id == id }) else { return }
        let oldName = fields[index].name
        guard oldName != Self.othersField else {
            fields[index].name = Self.othersField
            return
        }
        guard let newName = Self.normalizedFieldName(rawName),
              newName != Self.othersField,
              !fields.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(newName) == .orderedSame }) else {
            return
        }

        isLoading = true
        fields[index].name = newName
        for venueIndex in venues.indices where Self.normalizedField(venues[venueIndex].field) == oldName {
            venues[venueIndex].field = newName
        }
        isLoading = false

        saveFields()
        saveVenues()
        metadataVersion += 1
    }

    func setFieldColor(id: String, colorName: String?) {
        guard let index = fields.firstIndex(where: { $0.id == id }) else { return }
        fields[index].color = colorName
        metadataVersion += 1
    }

    func deleteField(id: String) {
        guard let field = fields.first(where: { $0.id == id }),
              field.name != Self.othersField else { return }
        let name = field.name

        isLoading = true
        fields.removeAll { $0.id == id }
        for venueIndex in venues.indices where Self.normalizedField(venues[venueIndex].field) == name {
            venues[venueIndex].field = nil
        }
        isLoading = false

        saveFields()
        saveVenues()
        metadataVersion += 1
    }

    private func colorName(forKey key: String) -> String? {
        if key.hasPrefix("field:") {
            guard let name = Self.normalizedFieldName(String(key.dropFirst("field:".count))) else { return nil }
            return fields.first(where: { $0.name == name })?.color
        }
        if key.hasPrefix("tier:"), let rank = Int(key.dropFirst("tier:".count)) {
            return tiers.first(where: { $0.rank == rank })?.color
        }
        return nil
    }

    private func color(named name: String?, default defaultColor: LabelColor) -> Color {
        LabelColor.color(named: name) ?? defaultColor.color
    }

    static func tierDefaultColor(_ tier: Int) -> LabelColor {
        switch tier {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        default: return .gray
        }
    }

    private func openDatabase() {
        let url = PaperStore.shared.dbURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            print("Error: Could not open metadata database at \(url.path)")
        } else {
            sqlite3_busy_timeout(db, 5000)
        }
    }

    private func closeDatabase() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    func reopen() {
        closeDatabase()
        openDatabase()
        createTablesIfNeeded()
        seedDefaultsIfNeeded()
        load()
    }

    private func createTablesIfNeeded() {
        let schema = """
        CREATE TABLE IF NOT EXISTS metadata_topics (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            query TEXT NOT NULL DEFAULT '',
            keywords_json TEXT NOT NULL DEFAULT '[]',
            color TEXT,
            icon TEXT,
            archived INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS metadata_fields (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            color TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS metadata_tiers (
            rank INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            points INTEGER NOT NULL,
            color TEXT,
            sort_order INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS metadata_venue_rules (
            id TEXT PRIMARY KEY,
            abbr TEXT NOT NULL,
            phrase TEXT NOT NULL,
            exact INTEGER NOT NULL DEFAULT 0,
            field_name TEXT,
            tier_rank INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS metadata_scoring (
            id INTEGER PRIMARY KEY DEFAULT 1,
            citation_breakpoints_json TEXT NOT NULL DEFAULT '[]',
            max_citation_points INTEGER NOT NULL DEFAULT 0,
            others_tier INTEGER NOT NULL DEFAULT 0
        );
        """

        var errorMsg: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, schema, nil, nil, &errorMsg) != SQLITE_OK {
            let error = errorMsg.map { String(cString: $0) } ?? "unknown error"
            print("Error creating metadata tables: \(error)")
            sqlite3_free(errorMsg)
        }

    }

    private func seedDefaultsIfNeeded() {
        guard countRows("metadata_topics") == 0,
              countRows("metadata_venue_rules") == 0,
              countRows("metadata_fields") == 0,
              countRows("metadata_tiers") == 0,
              countRows("metadata_scoring") == 0 else {
            return
        }

        isLoading = true
        topics = Self.defaultTracks
        venues = Self.defaultVenues
        fields = makeFields(from: venues)
        tiers = makeTiers(from: venues)
        citationBreakpoints = Self.defaultCitationBreakpoints
        maxCitationPoints = Self.defaultMaxCitationPoints
        isLoading = false

        saveTopics()
        saveFields()
        saveTiers()
        saveVenues()
        saveScoring()
    }

    private func load() {
        isLoading = true
        topics = loadTopics()
        let loadedFields = loadFields()
        tiers = loadTiers()
        venues = loadVenues()
        fields = ensureFields(in: loadedFields, cover: venues)
        loadScoring()
        isLoading = false
        metadataVersion += 1
    }

    private func persistIfReady(_ persist: () -> Void) {
        guard !isLoading else { return }
        persist()
        metadataVersion += 1
    }

    private func persistScoringRule(_ persist: () -> Void) {
        guard !isLoading else { return }
        persist()
        metadataVersion += 1
        rulesDirty = true
    }

    func markRulesApplied() {
        rulesDirty = false
    }

    // MARK: - Topic CRUD

    func addTopic(_ topic: TrackPref) {
        topics.append(topic)
    }

    func updateTopic(_ topic: TrackPref) {
        guard let index = topics.firstIndex(where: { $0.id == topic.id }) else { return }
        topics[index] = topic
    }

    func setTopicArchived(id: UUID, _ archived: Bool) {
        guard let index = topics.firstIndex(where: { $0.id == id }) else { return }
        topics[index].archived = archived
    }

    func deleteTopic(id: UUID) {
        topics.removeAll { $0.id == id }
    }

    func reorderTopics(from source: IndexSet, to destination: Int) {
        var active = topics.filter { !$0.archived }
        active.move(fromOffsets: source, toOffset: destination)
        let archived = topics.filter { $0.archived }
        topics = active + archived
    }

    private func saveTopics() {
        replace(table: "metadata_topics") {
            let sql = "INSERT INTO metadata_topics (id, name, query, keywords_json, color, icon, archived, sort_order) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
            for (index, topic) in topics.enumerated() {
                let keywordsData = (try? JSONEncoder().encode(topic.keywords)) ?? Data("[]".utf8)
                let keywords = String(data: keywordsData, encoding: .utf8) ?? "[]"
                execute(sql, bindings: [
                    topic.id.uuidString,
                    topic.name,
                    topic.query,
                    keywords,
                    topic.color,
                    topic.icon,
                    topic.archived ? 1 : 0,
                    index
                ])
            }
        }
    }

    private func saveFields() {
        replace(table: "metadata_fields") {
            for (index, field) in fields.compactMap({ field -> FieldPref? in
                guard let name = Self.normalizedFieldName(field.name) else { return nil }
                return FieldPref(id: field.id, name: name, color: field.color, sortOrder: field.sortOrder)
            }).enumerated() {
                execute(
                    "INSERT INTO metadata_fields (id, name, color, sort_order) VALUES (?, ?, ?, ?)",
                    bindings: [field.id, field.name, field.color, index]
                )
            }
        }
    }

    private func saveTiers() {
        replace(table: "metadata_tiers") {
            for (index, tier) in tiers.enumerated() {
                execute(
                    "INSERT INTO metadata_tiers (rank, name, points, color, sort_order) VALUES (?, ?, ?, ?, ?)",
                    bindings: [tier.rank, tier.name, tier.points, tier.color, index]
                )
            }
        }
    }

    private func saveVenues() {
        replace(table: "metadata_venue_rules") {
            for (index, venue) in venues.enumerated() {
                execute(
                    "INSERT INTO metadata_venue_rules (id, abbr, phrase, exact, field_name, tier_rank, sort_order) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    bindings: [
                        venue.id.uuidString,
                        venue.abbr,
                        venue.phrase,
                        venue.exact == true ? 1 : 0,
                        Self.normalizedField(venue.field),
                        venue.tier,
                        index
                    ]
                )
            }
        }
    }

    private func saveScoring() {
        let bpData = (try? JSONEncoder().encode(citationBreakpoints)) ?? Data("[]".utf8)
        let bpJson = String(data: bpData, encoding: .utf8) ?? "[]"

        let sql = """
        INSERT INTO metadata_scoring (id, citation_breakpoints_json, max_citation_points, others_tier)
        VALUES (1, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            citation_breakpoints_json = excluded.citation_breakpoints_json,
            max_citation_points = excluded.max_citation_points,
            others_tier = excluded.others_tier
        """
        execute(sql, bindings: [bpJson, maxCitationPoints, othersTier])
    }

    private func replace(table: String, body: () -> Void) {
        sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil)
        sqlite3_exec(db, "DELETE FROM \(table)", nil, nil, nil)
        body()
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    private func execute(_ sql: String, bindings: [Any?]) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        for (index, value) in bindings.enumerated() {
            bind(value, to: Int32(index + 1), in: stmt)
        }
        sqlite3_step(stmt)
    }

    private func bind(_ value: Any?, to index: Int32, in stmt: OpaquePointer?) {
        switch value {
        case let value as String:
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        case let value as Int:
            sqlite3_bind_int(stmt, index, Int32(value))
        case let value as Bool:
            sqlite3_bind_int(stmt, index, value ? 1 : 0)
        case .none:
            sqlite3_bind_null(stmt, index)
        default:
            sqlite3_bind_null(stmt, index)
        }
    }

    private func countRows(_ table: String) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \(table)", -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    private func loadTopics() -> [TrackPref] {
        let sql = "SELECT id, name, query, keywords_json, color, icon, archived FROM metadata_topics ORDER BY sort_order, name"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var rows: [TrackPref] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = UUID(uuidString: columnString(stmt, 0)) ?? UUID()
            let name = columnString(stmt, 1)
            let query = columnString(stmt, 2)
            let keywordsRaw = columnString(stmt, 3)
            let keywordsData = keywordsRaw.data(using: .utf8) ?? Data("[]".utf8)
            let keywords = (try? JSONDecoder().decode([String].self, from: keywordsData)) ?? []
            let color = columnOptionalString(stmt, 4)
            let icon = columnOptionalString(stmt, 5)
            let archived = sqlite3_column_int(stmt, 6) != 0
            rows.append(TrackPref(id: id, name: name, query: query, keywords: keywords, color: color, icon: icon, archived: archived))
        }
        return rows
    }

    private func loadFields() -> [FieldPref] {
        let sql = "SELECT id, name, color, sort_order FROM metadata_fields ORDER BY sort_order, name"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var rows: [FieldPref] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let name = Self.normalizedFieldName(columnString(stmt, 1)) else { continue }
            rows.append(FieldPref(
                id: columnString(stmt, 0),
                name: name,
                color: columnOptionalString(stmt, 2),
                sortOrder: Int(sqlite3_column_int(stmt, 3))
            ))
        }
        return rows
    }

    private func loadTiers() -> [TierPref] {
        let sql = "SELECT rank, name, points, color, sort_order FROM metadata_tiers ORDER BY sort_order, rank"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var rows: [TierPref] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rank = Int(sqlite3_column_int(stmt, 0))
            rows.append(TierPref(
                rank: rank,
                name: columnString(stmt, 1),
                points: Int(sqlite3_column_int(stmt, 2)),
                color: columnOptionalString(stmt, 3),
                sortOrder: Int(sqlite3_column_int(stmt, 4))
            ))
        }
        return rows
    }

    private func loadVenues() -> [VenuePref] {
        let sql = "SELECT id, abbr, phrase, exact, field_name, tier_rank FROM metadata_venue_rules ORDER BY sort_order, abbr"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var rows: [VenuePref] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(VenuePref(
                id: UUID(uuidString: columnString(stmt, 0)) ?? UUID(),
                abbr: columnString(stmt, 1),
                phrase: columnString(stmt, 2),
                tier: Int(sqlite3_column_int(stmt, 5)),
                field: Self.normalizedField(columnOptionalString(stmt, 4)),
                exact: sqlite3_column_int(stmt, 3) == 1
            ))
        }
        return rows
    }

    private func loadScoring() {
        let sql = "SELECT citation_breakpoints_json, max_citation_points, others_tier FROM metadata_scoring WHERE id = 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            let bpJson = columnString(stmt, 0)
            let bpData = bpJson.data(using: .utf8) ?? Data("[]".utf8)
            citationBreakpoints = Self.finiteCitationBreakpoints(
                (try? JSONDecoder().decode([CitationBreakpoint].self, from: bpData)) ?? []
            )
            maxCitationPoints = Int(sqlite3_column_int(stmt, 1))
            othersTier = Int(sqlite3_column_int(stmt, 2))
        }
    }

    private func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        sqlite3_column_text(stmt, index).map { String(cString: $0) } ?? ""
    }

    private func columnOptionalString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let raw = sqlite3_column_text(stmt, index) else { return nil }
        let value = String(cString: raw)
        return value.isEmpty ? nil : value
    }

    private func makeFields(from venues: [VenuePref]) -> [FieldPref] {
        let names = Set(venues.compactMap { Self.normalizedField($0.field) })
        let generated = names.sorted().enumerated().map { index, name in
            FieldPref(id: UUID().uuidString, name: name, color: Self.defaultFieldColor(name), sortOrder: index)
        }
        return ensureFields(in: generated, cover: venues)
    }

    private func ensureFields(in fields: [FieldPref], cover venues: [VenuePref]) -> [FieldPref] {
        var normalized = fields.compactMap { field -> FieldPref? in
            guard let name = Self.normalizedFieldName(field.name) else { return nil }
            return FieldPref(id: field.id, name: name, color: field.color, sortOrder: field.sortOrder)
        }

        var existing = Set(normalized.map(\.name))
        for venue in venues {
            guard let name = Self.normalizedField(venue.field), !existing.contains(name) else { continue }
            normalized.append(FieldPref(id: UUID().uuidString, name: name,
                                        color: Self.defaultFieldColor(name),
                                        sortOrder: normalized.count))
            existing.insert(name)
        }

        if !existing.contains(Self.othersField) {
            normalized.append(FieldPref(id: UUID().uuidString, name: Self.othersField,
                                        color: Self.defaultFieldColor(Self.othersField),
                                        sortOrder: normalized.count))
        }
        return normalized
    }

    static func defaultFieldColor(_ field: String?) -> String? {
        switch field {
        case "AI": return "pink"
        case "AR": return "purple"
        case "FM": return "red"
        case "PL": return "orange"
        case "SE": return "blue"
        case othersField: return "gray"
        default: return nil
        }
    }

    private func makeTiers(from venues: [VenuePref]) -> [TierPref] {
        let ranks = Set(venues.map(\.tier))
        return ranks.sorted().enumerated().map { index, rank in
            TierPref(
                rank: rank,
                name: "Tier \(rank)",
                points: Self.defaultPoints(for: rank),
                color: nil,
                sortOrder: index
            )
        }
    }

    static func defaultPoints(for rank: Int) -> Int {
        tierPoints[rank] ?? max(1, 12 - 2 * rank)
    }

    static let othersField = "Others"

    static func normalizedField(_ field: String?) -> String? {
        guard let value = field?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.caseInsensitiveCompare(othersField) == .orderedSame || value.caseInsensitiveCompare("OT") == .orderedSame {
            return nil
        }
        return value
    }

    static func normalizedFieldName(_ field: String?) -> String? {
        guard let value = field?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.caseInsensitiveCompare("OT") == .orderedSame {
            return nil
        }
        if value.caseInsensitiveCompare(othersField) == .orderedSame {
            return othersField
        }
        return value
    }

    // MARK: - Import / Export / Preset

    /// Scoring rules only (venues, tiers, fields, citation/others scoring). Topics
    /// are the user's literature libraries — deliberately excluded so importing a
    /// rules file never wipes their libraries.
    struct MetadataExport: Codable {
        struct VenueExport: Codable {
            var abbr: String
            var phrase: String
            var tier: Int
            var field: String?
            var exact: Bool?
        }
        struct TierExport: Codable {
            var rank: Int
            var name: String
            var points: Int
            var color: String?
        }
        struct FieldExport: Codable {
            var name: String
            var color: String?
        }
        struct ScoringExport: Codable {
            var citation_breakpoints: [CitationBreakpoint]
            var max_citation_points: Int
            var others_tier: Int?
        }

        var venues: [VenueExport]
        var tiers: [TierExport]
        var fields: [FieldExport]
        var scoring: ScoringExport
    }

    func exportMetadata() throws -> Data {
        let export = MetadataExport(
            venues: venues.map { .init(abbr: $0.abbr, phrase: $0.phrase, tier: $0.tier, field: Self.normalizedField($0.field), exact: $0.exact) },
            tiers: tiers.map { .init(rank: $0.rank, name: $0.name, points: $0.points, color: $0.color) },
            fields: fields.compactMap { field in
                guard let name = Self.normalizedFieldName(field.name) else { return nil }
                return .init(name: name, color: field.color)
            },
            scoring: .init(citation_breakpoints: citationBreakpoints, max_citation_points: maxCitationPoints, others_tier: othersTier)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    func importMetadata(from data: Data) throws {
        let decoded = try JSONDecoder().decode(MetadataExport.self, from: data)

        isLoading = true

        venues = decoded.venues.map {
            VenuePref(abbr: $0.abbr, phrase: $0.phrase, tier: $0.tier, field: Self.normalizedField($0.field), exact: $0.exact)
        }
        tiers = decoded.tiers.map {
            TierPref(rank: $0.rank, name: $0.name, points: $0.points, color: $0.color, sortOrder: 0)
        }
        fields = ensureFields(in: decoded.fields.enumerated().compactMap {
            guard let name = Self.normalizedFieldName($1.name) else { return nil }
            return FieldPref(id: UUID().uuidString, name: name, color: $1.color, sortOrder: $0)
        }, cover: venues)
        citationBreakpoints = Self.finiteCitationBreakpoints(decoded.scoring.citation_breakpoints)
        maxCitationPoints = decoded.scoring.max_citation_points
        othersTier = decoded.scoring.others_tier ?? 0

        isLoading = false

        saveFields()
        saveTiers()
        saveVenues()
        saveScoring()
        metadataVersion += 1
        rulesDirty = true
    }

    func resetToPreset() {
        isLoading = true
        topics = Self.defaultTracks
        venues = Self.defaultVenues
        fields = makeFields(from: venues)
        tiers = makeTiers(from: venues)
        citationBreakpoints = Self.defaultCitationBreakpoints
        maxCitationPoints = Self.defaultMaxCitationPoints
        othersTier = 0
        isLoading = false

        saveTopics()
        saveFields()
        saveTiers()
        saveVenues()
        saveScoring()
        metadataVersion += 1
        rulesDirty = true
    }

    // MARK: - Built-in defaults

    static let tierPoints: [Int: Int] = [1: 10, 2: 7, 3: 5, 4: 2, 5: 1]

    static let defaultCitationBreakpoints: [CitationBreakpoint] = [
        CitationBreakpoint(up_to: 10, points_per_citation: 0.5),
        CitationBreakpoint(up_to: 50, points_per_citation: 0.2)
    ]
    static let defaultMaxCitationPoints: Int = 40

    static func finiteCitationBreakpoints(_ breakpoints: [CitationBreakpoint]) -> [CitationBreakpoint] {
        breakpoints
            .filter { $0.up_to != nil }
            .sorted { ($0.up_to ?? 0) < ($1.up_to ?? 0) }
    }

    static let defaultTracks: [TrackPref] = [
        TrackPref(name: "SAT", query: "SAT solver boolean satisfiability",
                  keywords: ["sat solver", "boolean satisfiability", "propositional satisfiability",
                             "cdcl", "conflict-driven clause learning", "maxsat", "sat solving"],
                  color: "purple", icon: "function"),
        TrackPref(name: "SMT", query: "satisfiability modulo theories SMT solver",
                  keywords: ["smt solver", "satisfiability modulo theories", "smt",
                             "z3", "cvc5", "theory solver", "bit-vector"],
                  color: "indigo", icon: "cpu"),
        TrackPref(name: "CP", query: "constraint programming constraint satisfaction",
                  keywords: ["constraint programming", "constraint satisfaction", "constraint solver",
                             "constraint propagation", "global constraint", "csp"],
                  color: "teal", icon: "chart.bar")
    ]

    static let defaultVenues: [VenuePref] = [
        VenuePref(abbr: "ICSE",  phrase: "international conference on software engineering", tier: 1, field: "SE"),
        VenuePref(abbr: "FSE",   phrase: "acm on software engineering", tier: 1, field: "SE"),
        VenuePref(abbr: "ASE",   phrase: "automated software engineering", tier: 1, field: "SE"),
        VenuePref(abbr: "ISSTA", phrase: "software testing and analysis", tier: 1, field: "SE"),
        VenuePref(abbr: "TSE",   phrase: "transactions on software engineering", tier: 1, field: "SE"),
        VenuePref(abbr: "TOSEM", phrase: "software engineering and methodology", tier: 1, field: "SE"),
        VenuePref(abbr: "PACMPL", phrase: "acm on programming languages", tier: 1, field: "PL"),
        VenuePref(abbr: "TOPLAS", phrase: "transactions on programming languages and systems", tier: 1, field: "PL"),
        VenuePref(abbr: "CAV",   phrase: "computer aided verification", tier: 1, field: "FM"),
        VenuePref(abbr: "CP",    phrase: "constraint programming", tier: 1, field: "AR"),
        VenuePref(abbr: "SAT",   phrase: "satisfiability testing", tier: 1, field: "AR"),
        VenuePref(abbr: "JAR",   phrase: "journal of automated reasoning", tier: 1, field: "AR"),
        VenuePref(abbr: "AIJ",   phrase: "artificial intelligence", tier: 1, field: "AI", exact: true),
        VenuePref(abbr: "JAIR",  phrase: "journal of artificial intelligence research", tier: 1, field: "AI"),
        VenuePref(abbr: "AAAI",  phrase: "aaai conference on artificial intelligence", tier: 1, field: "AI"),
        VenuePref(abbr: "IJCAI", phrase: "international joint conference on artificial intelligence", tier: 1, field: "AI"),
        VenuePref(abbr: "NeurIPS", phrase: "neural information processing systems", tier: 1, field: "AI"),
        VenuePref(abbr: "ICLR",  phrase: "learning representations", tier: 1, field: "AI"),
        VenuePref(abbr: "ICML",  phrase: "international conference on machine learning", tier: 1, field: "AI"),
        VenuePref(abbr: "TACAS", phrase: "tools and algorithms for the construction", tier: 2, field: "FM"),
        VenuePref(abbr: "CADE",  phrase: "automated deduction", tier: 2, field: "AR"),
        VenuePref(abbr: "IJCAR", phrase: "joint conference on automated reasoning", tier: 2, field: "AR"),
        VenuePref(abbr: "LICS",  phrase: "logic in computer science", tier: 2, field: "FM"),
        VenuePref(abbr: "FMCAD", phrase: "formal methods in computer-aided design", tier: 2, field: "FM"),
        VenuePref(abbr: "CONCUR", phrase: "concurrency theory", tier: 2, field: "FM"),
        VenuePref(abbr: "ESOP",  phrase: "european symposium on programming", tier: 2, field: "PL"),
        VenuePref(abbr: "ECOOP", phrase: "object-oriented programming", tier: 2, field: "PL"),
        VenuePref(abbr: "ICAPS", phrase: "automated planning and scheduling", tier: 2, field: "AI"),
        VenuePref(abbr: "FM",    phrase: "international symposium on formal methods", tier: 2, field: "FM"),
        VenuePref(abbr: "VMCAI", phrase: "verification, model checking", tier: 2, field: "FM"),
        VenuePref(abbr: "ITP",   phrase: "interactive theorem proving", tier: 2, field: "FM"),
        VenuePref(abbr: "EMSE",  phrase: "empirical software engineering", tier: 2, field: "SE"),
        VenuePref(abbr: "TOCL",  phrase: "transactions on computational logic", tier: 2, field: "FM"),
        VenuePref(abbr: "FMSD",  phrase: "formal methods in system design", tier: 2, field: "FM"),
        VenuePref(abbr: "STTT",  phrase: "software tools for technology transfer", tier: 2, field: "FM"),
        VenuePref(abbr: "FAoC",  phrase: "formal aspects of computing", tier: 2, field: "FM"),
        VenuePref(abbr: "SCP",   phrase: "science of computer programming", tier: 2, field: "PL"),
        VenuePref(abbr: "ICST",  phrase: "software testing, verification and validation", tier: 3, field: "SE"),
        VenuePref(abbr: "SANER", phrase: "software analysis, evolution and reengineering", tier: 3, field: "SE"),
        VenuePref(abbr: "ICSME", phrase: "software maintenance and evolution", tier: 3, field: "SE"),
        VenuePref(abbr: "MSR",   phrase: "mining software repositories", tier: 3, field: "SE"),
        VenuePref(abbr: "SEFM",  phrase: "software engineering and formal methods", tier: 3, field: "FM"),
        VenuePref(abbr: "ICLP",  phrase: "logic programming", tier: 3, field: "AR"),
        VenuePref(abbr: "TABLEAUX", phrase: "analytic tableaux", tier: 3, field: "AR"),
        VenuePref(abbr: "SOCS",  phrase: "combinatorial search", tier: 3, field: "AI"),
        VenuePref(abbr: "EPTCS", phrase: "electronic proceedings in theoretical computer science", tier: 3, field: "FM"),
        VenuePref(abbr: "arXiv", phrase: "arxiv", tier: 4, field: nil)
    ]
}
