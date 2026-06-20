import Foundation
import SwiftUI

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
    var pdfLocalPath: String?
    var pdfStatus: String?
    var track: String
    var score: Double
    var tier: Int
    var status: PaperStatus
    var isRecommended: Bool
    var recommendedAt: Date?
    var recommendationReason: String
    var tags: [String]     { didSet { _searchText = nil } }
    var note: String       { didSet { _searchText = nil } }
    var abstractZh: String
    var referencedWorkIDs: [String]
    var relatedWorkIDs: [String]
    var statusChangedAt: Date?
    var addedAt: Date?

    private var _searchText: String?
    var searchText: String {
        if let cached = _searchText { return cached }
        let blob = ([title, abstract, venue, venueAbbr, note] + authors + tags)
            .joined(separator: " ")
            .lowercased()
        _searchText = blob
        return blob
    }

    var abstractWordCount: Int {
        abstract.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

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
        note: String = "", abstractZh: String = "",
        referencedWorkIDs: [String] = [], relatedWorkIDs: [String] = [],
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
        self.note = note
        self.abstractZh = abstractZh
        self.referencedWorkIDs = referencedWorkIDs
        self.relatedWorkIDs = relatedWorkIDs
        self.statusChangedAt = statusChangedAt
        self.addedAt = addedAt
    }
}
