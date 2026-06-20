import Foundation

// MARK: - OpenAlex API DTOs

struct OpenAlexSource: Decodable {
    var displayName: String?
    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
}

struct OpenAlexLocation: Decodable {
    var source: OpenAlexSource?
    var landingPageUrl: String?
    var pdfUrl: String?
    enum CodingKeys: String, CodingKey {
        case source
        case landingPageUrl = "landing_page_url"
        case pdfUrl = "pdf_url"
    }
}

struct OpenAlexAuthor: Decodable {
    var displayName: String?
    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
}

struct OpenAlexAuthorship: Decodable {
    var author: OpenAlexAuthor?
}

struct OpenAlexOpenAccess: Decodable {
    var oaUrl: String?
    enum CodingKeys: String, CodingKey { case oaUrl = "oa_url" }
}

struct OpenAlexWork: Decodable {
    var id: String
    var doi: String?
    var title: String?
    var displayName: String?
    var authorships: [OpenAlexAuthorship]?
    var publicationYear: Int?
    var publicationDate: String?
    var citedByCount: Int?
    var abstractInvertedIndex: [String: [Int]]?
    var primaryLocation: OpenAlexLocation?
    var openAccess: OpenAlexOpenAccess?
    var referencedWorks: [String]?
    var relatedWorks: [String]?

    enum CodingKeys: String, CodingKey {
        case id, doi, title, authorships
        case displayName = "display_name"
        case publicationYear = "publication_year"
        case publicationDate = "publication_date"
        case citedByCount = "cited_by_count"
        case abstractInvertedIndex = "abstract_inverted_index"
        case primaryLocation = "primary_location"
        case openAccess = "open_access"
        case referencedWorks = "referenced_works"
        case relatedWorks = "related_works"
    }
}

struct OpenAlexMeta: Decodable {
    var nextCursor: String?
    enum CodingKeys: String, CodingKey { case nextCursor = "next_cursor" }
}

struct OpenAlexResponse: Decodable {
    var meta: OpenAlexMeta?
    var results: [OpenAlexWork]?
}

// MARK: - Fetcher Class

class OpenAlexFetcher: @unchecked Sendable {
    let config: AppConfig
    let scorer: VenueScorer

    struct FetchFailure {
        var trackName: String
        var error: Error
    }

    enum FetchError: LocalizedError {
        case allTracksFailed([FetchFailure])

        var errorDescription: String? {
            switch self {
            case .allTracksFailed(let failures):
                let names = failures.map(\.trackName).joined(separator: ", ")
                return "All OpenAlex track fetches failed: \(names)"
            }
        }
    }

    init(config: AppConfig, venues: [VenuePref] = []) {
        self.config = config
        self.scorer = VenueScorer(config: config, venues: venues)
    }

    private func restoreAbstract(from index: [String: [Int]]?) -> String {
        guard let index = index else { return "" }
        var wordsList: [(Int, String)] = []
        for (word, positions) in index {
            for pos in positions {
                wordsList.append((pos, word))
            }
        }
        wordsList.sort { $0.0 < $1.0 }
        return wordsList.map { $0.1 }.joined(separator: " ")
    }

    private func isKeywordMatched(text: String, keyword: String) -> Bool {
        let escapedPattern = NSRegularExpression.escapedPattern(for: keyword.lowercased())
        let pattern = "\\b\(escapedPattern)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private func isRelevant(paper: Paper, trackName: String) -> Bool {
        let titleLower = paper.title.lowercased()
        let text = "\(titleLower) \(paper.abstract.lowercased())"

        if let titleBlacklist = config.filters?.title_blacklist {
            for token in titleBlacklist where titleLower.contains(token.lowercased()) {
                return false
            }
        }

        if let sourceBlacklist = config.filters?.source_blacklist {
            let venueLower = paper.venue.lowercased()
            for token in sourceBlacklist where venueLower.contains(token.lowercased()) {
                return false
            }
        }

        guard let trackConfig = config.tracks[trackName] else { return false }
        guard !trackConfig.keywords.isEmpty else { return true }
        return trackConfig.keywords.contains { isKeywordMatched(text: text, keyword: $0) }
    }

    private func searchPapers(
        query: String,
        fromDate: String,
        toDate: String,
        maxResults: Int
    ) async throws -> [OpenAlexWork] {
        var collectedWorks: [OpenAlexWork] = []
        var cursor = "*"

        while collectedWorks.count < maxResults {
            var filters = [
                "from_publication_date:\(fromDate)",
                "to_publication_date:\(toDate)",
                "type:article"
            ]
            if !config.openalex.topic_filter.isEmpty {
                filters.append(config.openalex.topic_filter)
            }

            var components = URLComponents(string: config.openalex.base_url)
            var queryItems = [
                URLQueryItem(name: "search", value: query),
                URLQueryItem(name: "filter", value: filters.joined(separator: ",")),
                URLQueryItem(name: "sort", value: "publication_date:desc,relevance_score:desc"),
                URLQueryItem(name: "per_page", value: String(min(config.openalex.per_page, maxResults - collectedWorks.count))),
                URLQueryItem(name: "cursor", value: cursor),
                URLQueryItem(name: "select", value: Self.displayFields)
            ]
            if !config.openalex.mailto.isEmpty {
                queryItems.append(URLQueryItem(name: "mailto", value: config.openalex.mailto))
            }
            components?.queryItems = queryItems
            guard let url = components?.url else { throw URLError(.badURL) }

            let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            let alexResponse = try JSONDecoder().decode(OpenAlexResponse.self, from: data)
            guard let results = alexResponse.results else { break }
            collectedWorks.append(contentsOf: results)

            guard let nextCursor = alexResponse.meta?.nextCursor, !results.isEmpty else { break }
            cursor = nextCursor

            try await Task.sleep(nanoseconds: 100_000_000)
        }

        return collectedWorks
    }

    func parseWork(_ work: OpenAlexWork, track: String) -> Paper {
        let venue = work.primaryLocation?.source?.displayName ?? ""
        let citations = work.citedByCount ?? 0
        let (tier, venueAbbr, score) = scorer.evaluate(venue: venue, citations: citations)

        let authors = work.authorships?.compactMap { $0.author?.displayName } ?? []
        let abstract = restoreAbstract(from: work.abstractInvertedIndex)
        let landingPage = work.primaryLocation?.landingPageUrl ?? work.doi ?? work.id
        let pdf = work.primaryLocation?.pdfUrl ?? work.openAccess?.oaUrl

        return Paper(
            id: work.id,
            doi: work.doi,
            title: work.displayName ?? work.title ?? "",
            authors: authors,
            publicationDate: work.publicationDate ?? "",
            publicationYear: work.publicationYear,
            venue: venue,
            venueAbbr: venueAbbr,
            citedByCount: citations,
            abstract: abstract,
            landingPageUrl: landingPage,
            pdfUrl: pdf,
            track: track,
            score: score,
            tier: tier,
            referencedWorkIDs: Self.uniqueWorkIDs(work.referencedWorks ?? []),
            relatedWorkIDs: Self.uniqueWorkIDs(work.relatedWorks ?? [])
        )
    }

    private func dedupeAndMergeTracks(papers: [Paper]) -> [Paper] {
        var byId: [String: Paper] = [:]
        for paper in papers {
            guard !paper.id.isEmpty else { continue }
            if let existing = byId[paper.id] {
                var trackSet = Set(existing.track.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                })
                if !paper.track.isEmpty {
                    trackSet.insert(paper.track)
                }
                existing.track = trackSet.sorted().joined(separator: ",")
                existing.score = max(existing.score, paper.score)
                existing.referencedWorkIDs = Self.uniqueWorkIDs(existing.referencedWorkIDs + paper.referencedWorkIDs)
                existing.relatedWorkIDs = Self.uniqueWorkIDs(existing.relatedWorkIDs + paper.relatedWorkIDs)
            } else {
                byId[paper.id] = paper
            }
        }
        return Array(byId.values)
    }

    func fetch(days: Int? = nil, maxResults: Int? = nil) async throws -> (papers: [Paper], totalRaw: Int, totalFiltered: Int, failedTracks: [String]) {
        let daysToFetch = days ?? config.openalex.default_days
        let resultsCap = maxResults ?? config.openalex.default_max_results

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let today = Date()
        guard let fromDay = Calendar.current.date(byAdding: .day, value: -(daysToFetch - 1), to: today) else {
            throw URLError(.cannotParseResponse)
        }

        let fromDate = dateFormatter.string(from: fromDay)
        let toDate = dateFormatter.string(from: today)

        var allPapers: [Paper] = []
        var totalRaw = 0
        var failures: [FetchFailure] = []
        var fetchedTracks = 0

        for (trackName, trackConfig) in config.tracks {
            guard !trackConfig.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            fetchedTracks += 1
            do {
                let works = try await searchPapers(
                    query: trackConfig.query,
                    fromDate: fromDate,
                    toDate: toDate,
                    maxResults: resultsCap
                )
                totalRaw += works.count

                let parsed = works.map { parseWork($0, track: trackName) }
                allPapers.append(contentsOf: parsed.filter { isRelevant(paper: $0, trackName: trackName) })
            } catch {
                failures.append(FetchFailure(trackName: trackName, error: error))
            }
        }

        if fetchedTracks > 0, failures.count == fetchedTracks {
            throw FetchError.allTracksFailed(failures)
        }

        let merged = dedupeAndMergeTracks(papers: allPapers)
        return (merged, totalRaw, merged.count, failures.map(\.trackName))
    }

    private static let displayFields =
        "id,doi,title,display_name,authorships,publication_year,publication_date,cited_by_count,abstract_inverted_index,primary_location,open_access,referenced_works,related_works"

    private static func uniqueWorkIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in ids {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        var userAgent = "FacetX/1.0"
        if !config.openalex.mailto.isEmpty {
            userAgent += " (mailto:\(config.openalex.mailto))"
        }
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private func decodeWorks(from data: Data) -> [OpenAlexWork] {
        (try? JSONDecoder().decode(OpenAlexResponse.self, from: data))?.results ?? []
    }

    // MARK: - Manual import helpers

    func fetchByDOI(_ doi: String) async -> Paper? {
        let normalised = doi
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://doi.org/", with: "")
            .replacingOccurrences(of: "http://doi.org/", with: "")
            .replacingOccurrences(of: "doi.org/", with: "")
        guard !normalised.isEmpty else { return nil }

        var components = URLComponents(string: config.openalex.base_url)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "filter", value: "doi:\(normalised)"),
            URLQueryItem(name: "select", value: Self.displayFields)
        ]
        if !config.openalex.mailto.isEmpty {
            items.append(URLQueryItem(name: "mailto", value: config.openalex.mailto))
        }
        components?.queryItems = items
        guard let url = components?.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return decodeWorks(from: data).first.map { parseWork($0, track: "") }
        } catch {
            print("OpenAlex fetchByDOI failed: \(error)")
            return nil
        }
    }

    func fetchByTitle(_ title: String, limit: Int = 5) async -> [Paper] {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var components = URLComponents(string: config.openalex.base_url)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "search", value: title),
            URLQueryItem(name: "per_page", value: String(min(limit, 25))),
            URLQueryItem(name: "select", value: Self.displayFields)
        ]
        if !config.openalex.mailto.isEmpty {
            items.append(URLQueryItem(name: "mailto", value: config.openalex.mailto))
        }
        components?.queryItems = items
        guard let url = components?.url else { return [] }
        do {
            let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            return decodeWorks(from: data).map { parseWork($0, track: "") }
        } catch {
            print("OpenAlex fetchByTitle failed: \(error)")
            return []
        }
    }
}
