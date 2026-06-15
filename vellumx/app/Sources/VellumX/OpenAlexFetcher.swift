import Foundation

// MARK: - OpenAlex API DTOs

struct OpenAlexSource: Decodable {
    var displayName: String?
    
    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
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
    
    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

struct OpenAlexAuthorship: Decodable {
    var author: OpenAlexAuthor?
}

struct OpenAlexOpenAccess: Decodable {
    var oaUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case oaUrl = "oa_url"
    }
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
        case relatedWorks = "related_works"
    }
}

struct OpenAlexMeta: Decodable {
    var nextCursor: String?
    
    enum CodingKeys: String, CodingKey {
        case nextCursor = "next_cursor"
    }
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
        
        // 1. Title blacklist check
        if let titleBlacklist = config.filters?.title_blacklist {
            for token in titleBlacklist {
                if titleLower.contains(token.lowercased()) {
                    return false
                }
            }
        }
        
        // 2. Source blacklist check
        if let sourceBlacklist = config.filters?.source_blacklist {
            let venueLower = paper.venue.lowercased()
            for token in sourceBlacklist {
                if venueLower.contains(token.lowercased()) {
                    return false
                }
            }
        }
        
        // 3. Track keywords check
        guard let trackConfig = config.tracks[trackName] else { return false }
        for keyword in trackConfig.keywords {
            if isKeywordMatched(text: text, keyword: keyword) {
                return true
            }
        }
        
        return false
    }
    
    private func searchPapers(
        query: String,
        fromDate: String,
        toDate: String,
        maxResults: Int
    ) async throws -> [OpenAlexWork] {
        var collectedWorks: [OpenAlexWork] = []
        var cursor = "*"
        let baseUrl = config.openalex.base_url
        let perPage = config.openalex.per_page
        let topicFilter = config.openalex.topic_filter
        let mailto = config.openalex.mailto

        let session = URLSession.shared
        
        while collectedWorks.count < maxResults {
            var filters = [
                "from_publication_date:\(fromDate)",
                "to_publication_date:\(toDate)",
                "type:article"
            ]
            if !topicFilter.isEmpty {
                filters.append(topicFilter)
            }
            
            var components = URLComponents(string: baseUrl)
            var queryItems = [
                URLQueryItem(name: "search", value: query),
                URLQueryItem(name: "filter", value: filters.joined(separator: ",")),
                URLQueryItem(name: "sort", value: "publication_date:desc,relevance_score:desc"),
                URLQueryItem(name: "per_page", value: String(min(perPage, maxResults - collectedWorks.count))),
                URLQueryItem(name: "cursor", value: cursor),
                URLQueryItem(name: "select", value: "id,doi,title,display_name,authorships,publication_year,publication_date,cited_by_count,abstract_inverted_index,primary_location,open_access")
            ]
            
            if !mailto.isEmpty {
                queryItems.append(URLQueryItem(name: "mailto", value: mailto))
            }

            components?.queryItems = queryItems
            
            guard let url = components?.url else {
                throw URLError(.badURL)
            }
            
            var request = URLRequest(url: url)
            var userAgent = "VellumX/1.0"
            if !mailto.isEmpty {
                userAgent += " (mailto:\(mailto))"
            }
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            let decoder = JSONDecoder()
            let alexResponse = try decoder.decode(OpenAlexResponse.self, from: data)
            
            guard let results = alexResponse.results else { break }
            collectedWorks.append(contentsOf: results)
            
            guard let nextCursor = alexResponse.meta?.nextCursor, !results.isEmpty else { break }
            cursor = nextCursor
            
            // Rate limit friendliness
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
        
        return collectedWorks
    }
    
    private func parseWork(_ work: OpenAlexWork, track: String) -> Paper {
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
            tier: tier
        )
    }
    
    private func dedupeAndMergeTracks(papers: [Paper]) -> [Paper] {
        var byId: [String: Paper] = [:]
        for paper in papers {
            let pid = paper.id
            if pid.isEmpty { continue }
            
            if let existing = byId[pid] {
                // Combine tracks
                let existingTracks = existing.track.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                var trackSet = Set(existingTracks)
                if !paper.track.isEmpty {
                    trackSet.insert(paper.track)
                }
                existing.track = trackSet.sorted().joined(separator: ",")
                existing.score = max(existing.score, paper.score)
            } else {
                byId[pid] = paper
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
        
        let fromDateStr = dateFormatter.string(from: fromDay)
        let toDateStr = dateFormatter.string(from: today)
        
        var allPapers: [Paper] = []
        var totalRaw = 0
        var failures: [FetchFailure] = []
        
        for (trackName, trackConfig) in config.tracks {
            print("Fetching OpenAlex works for track [\(trackName)]...")
            do {
                let works = try await searchPapers(
                    query: trackConfig.query,
                    fromDate: fromDateStr,
                    toDate: toDateStr,
                    maxResults: resultsCap
                )
                totalRaw += works.count
                
                let parsed = works.map { parseWork($0, track: trackName) }
                let relevant = parsed.filter { isRelevant(paper: $0, trackName: trackName) }
                print("Track [\(trackName)]: found \(works.count) raw works, kept \(relevant.count) relevant")
                
                allPapers.append(contentsOf: relevant)
            } catch {
                print("Error searching papers for track \(trackName): \(error)")
                failures.append(FetchFailure(trackName: trackName, error: error))
            }
        }

        if failures.count == config.tracks.count {
            throw FetchError.allTracksFailed(failures)
        }
        
        let merged = dedupeAndMergeTracks(papers: allPapers)
        return (merged, totalRaw, merged.count, failures.map(\.trackName))
    }

    // MARK: - Related papers (on-demand; used by the detail view)

    /// OpenAlex `select` field set for list/single fetches that feed `parseWork`.
    private static let displayFields =
        "id,doi,title,display_name,authorships,publication_year,publication_date,cited_by_count,abstract_inverted_index,primary_location,open_access"

    /// OpenAlex work IDs are full URLs (`https://openalex.org/W123`); filters and
    /// the single-work endpoint take the bare `W123`.
    static func stripOpenAlexId(_ id: String) -> String {
        if let slash = id.lastIndex(of: "/") {
            return String(id[id.index(after: slash)...])
        }
        return id
    }

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        var userAgent = "VellumX/1.0"
        if !config.openalex.mailto.isEmpty {
            userAgent += " (mailto:\(config.openalex.mailto))"
        }
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private func decodeWorks(from data: Data) -> [OpenAlexWork] {
        (try? JSONDecoder().decode(OpenAlexResponse.self, from: data))?.results ?? []
    }

    /// Fetches a single work, including its `related_works` ID list.
    private func fetchWork(id: String) async -> OpenAlexWork? {
        let bare = Self.stripOpenAlexId(id)
        var components = URLComponents(string: "\(config.openalex.base_url)/\(bare)")
        var items = [URLQueryItem(name: "select", value: "\(Self.displayFields),related_works")]
        if !config.openalex.mailto.isEmpty {
            items.append(URLQueryItem(name: "mailto", value: config.openalex.mailto))
        }
        components?.queryItems = items
        guard let url = components?.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(OpenAlexWork.self, from: data)
        } catch {
            print("OpenAlex fetchWork failed: \(error)")
            return nil
        }
    }

    /// Batch-fetches works by ID (chunked ≤50 per request via the `openalex_id`
    /// OR filter), parses them, and returns `Paper`s in the requested order.
    /// Public so single-item and batch "update from OpenAlex" can reuse it.
    func fetchWorksByIds(_ ids: [String]) async -> [Paper] {
        guard !ids.isEmpty else { return [] }
        let bareIds = ids.map(Self.stripOpenAlexId)
        var byId: [String: Paper] = [:]

        for start in stride(from: 0, to: bareIds.count, by: 50) {
            let chunk = Array(bareIds[start..<min(start + 50, bareIds.count)])
            var components = URLComponents(string: config.openalex.base_url)
            var items = [
                URLQueryItem(name: "filter", value: "openalex_id:\(chunk.joined(separator: "|"))"),
                URLQueryItem(name: "per_page", value: "50"),
                URLQueryItem(name: "select", value: Self.displayFields)
            ]
            if !config.openalex.mailto.isEmpty {
                items.append(URLQueryItem(name: "mailto", value: config.openalex.mailto))
            }
            components?.queryItems = items
            guard let url = components?.url else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url))
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                for work in decodeWorks(from: data) {
                    byId[Self.stripOpenAlexId(work.id)] = parseWork(work, track: "")
                }
            } catch {
                print("OpenAlex fetchWorksByIds failed: \(error)")
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        // Preserve the input order (related_works is relevance-ordered).
        return bareIds.compactMap { byId[$0] }
    }

    /// Similar papers: the target work's `related_works`, scored and ordered.
    func fetchSimilar(workId: String, limit: Int = 25) async -> [Paper] {
        guard let work = await fetchWork(id: workId),
              let related = work.relatedWorks, !related.isEmpty else { return [] }
        return await fetchWorksByIds(Array(related.prefix(limit)))
    }

    // MARK: - Manual import helpers

    /// Fetch a single work by DOI. Strips any "https://doi.org/" prefix before
    /// sending to the OpenAlex `filter=doi:` parameter.
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

    /// Full-text title search returning up to `limit` results. Does not apply
    /// date, type, or topic filters so it can surface older or non-article works.
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

    /// Papers citing the target work, most-cited first.
    func fetchCitedBy(workId: String, limit: Int = 25) async -> [Paper] {
        let bare = Self.stripOpenAlexId(workId)
        var components = URLComponents(string: config.openalex.base_url)
        var items = [
            URLQueryItem(name: "filter", value: "cites:\(bare)"),
            URLQueryItem(name: "sort", value: "cited_by_count:desc"),
            URLQueryItem(name: "per_page", value: String(min(limit, 200))),
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
            print("OpenAlex fetchCitedBy failed: \(error)")
            return []
        }
    }
}
