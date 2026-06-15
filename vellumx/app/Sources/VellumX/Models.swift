import Foundation
import SwiftUI

struct PaperCollection: Identifiable, Equatable {
    var id: String
    var name: String
    var color: String?
    /// SF Symbol name; `nil` falls back to a plain folder.
    var icon: String?
    /// Parent collection id; `nil` (or an unknown id) makes this a root folder.
    var parentId: String?
    init(id: String = UUID().uuidString, name: String, color: String? = nil,
         icon: String? = nil, parentId: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.parentId = parentId
    }
}

enum PaperStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case read = "read"
    case starred = "starred"
    case skip = "skip"

    var displayName: String {
        switch self {
        case .pending:     return "Pending"
        case .read:        return "Read"
        case .starred:     return "Starred"
        case .skip:        return "Skip"
        }
    }

    var iconName: String {
        switch self {
        case .pending:     return "clock"
        case .read:        return "checkmark.circle"
        case .starred:     return "star"
        case .skip:        return "eye.slash"
        }
    }

    var iconColor: Color {
        switch self {
        case .pending:     return .blue
        case .read:        return .green
        case .starred:     return .yellow
        case .skip:        return .secondary
        }
    }
}

/// Lightweight in-memory paper DTO used by the UI layer.
/// Persistence is handled by `PaperStore` via SQLite.
final class Paper: Identifiable {
    var id: String
    var doi: String?
    var title: String      { didSet { _searchText = nil } }
    var authors: [String]  { didSet { _searchText = nil } }
    var publicationDate: String
    var publicationYear: Int?
    var venue: String      { didSet { _searchText = nil } }
    var venueAbbr: String  { didSet { _searchText = nil } }
    var citedByCount: Int
    var abstract: String   { didSet { _searchText = nil } }
    var landingPageUrl: String
    var pdfUrl: String?
    /// Relative path of the downloaded PDF under the storage directory
    /// (`pdfs/<id>.pdf`); `nil` until a validated PDF is fetched.
    var pdfLocalPath: String?
    /// Raw `PdfStatus` rawValue; `nil` means no fetch has been attempted.
    var pdfStatus: String?
    var track: String
    var score: Double
    var tier: Int
    var status: PaperStatus
    var isRecommended: Bool
    var recommendedAt: Date?
    var recommendationReason: String
    var tags: [String]     { didSet { _searchText = nil } }
    var collectionIds: [String]
    var note: String       { didSet { _searchText = nil } }
    var abstractZh: String
    /// When the paper entered its current status (set on every status change).
    var statusChangedAt: Date?
    /// When the paper was first added to the library.
    var addedAt: Date?

    /// Lazily-built, lowercased concatenation of the searchable fields. Cached
    /// so per-keystroke filtering doesn't re-lowercase long abstracts for every
    /// paper; invalidated automatically whenever a searchable field is mutated
    /// (including in-place tag/note edits via `PaperStore`).
    private var _searchText: String?
    var searchText: String {
        if let cached = _searchText { return cached }
        let blob = ([title, abstract, venue, venueAbbr, note] + authors + tags)
            .joined(separator: " ")
            .lowercased()
        _searchText = blob
        return blob
    }

    /// Whitespace-separated token count of the abstract; zero if empty.
    var abstractWordCount: Int {
        abstract.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Rounded-up reading time at 220 wpm — a typical adult skim pace for
    /// dense academic prose. Returns `nil` when there's no abstract to read.
    var abstractReadingMinutes: Int? {
        let words = abstractWordCount
        guard words > 0 else { return nil }
        return max(1, Int((Double(words) / 220.0).rounded(.up)))
    }

    init(
        id: String, doi: String? = nil, title: String,
        authors: [String] = [], publicationDate: String = "",
        publicationYear: Int? = nil, venue: String = "",
        venueAbbr: String = "", citedByCount: Int = 0,
        abstract: String = "", landingPageUrl: String = "",
        pdfUrl: String? = nil, pdfLocalPath: String? = nil,
        pdfStatus: String? = nil, track: String = "",
        score: Double = 0.0, tier: Int = 0,
        status: PaperStatus = .pending,
        isRecommended: Bool = false, recommendedAt: Date? = nil,
        recommendationReason: String = "",
        tags: [String] = [],
        collectionIds: [String] = [],
        note: String = "", abstractZh: String = "",
        statusChangedAt: Date? = nil, addedAt: Date? = nil
    ) {
        self.id = id
        self.doi = doi
        self.title = title
        self.authors = authors
        self.publicationDate = publicationDate
        self.publicationYear = publicationYear
        self.venue = venue
        self.venueAbbr = venueAbbr
        self.citedByCount = citedByCount
        self.abstract = abstract
        self.landingPageUrl = landingPageUrl
        self.pdfUrl = pdfUrl
        self.pdfLocalPath = pdfLocalPath
        self.pdfStatus = pdfStatus
        self.track = track
        self.score = score
        self.tier = tier
        self.status = status
        self.isRecommended = isRecommended
        self.recommendedAt = recommendedAt
        self.recommendationReason = recommendationReason
        self.tags = tags
        self.collectionIds = collectionIds
        self.note = note
        self.abstractZh = abstractZh
        self.statusChangedAt = statusChangedAt
        self.addedAt = addedAt
    }
}
