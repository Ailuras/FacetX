import Foundation

class VenueScorer {
    let config: AppConfig

    private let exactMatches: [String: (tier: Int, abbr: String)]
    private let substringMatches: [(phrase: String, tier: Int, abbr: String)]

    init(config: AppConfig, venues: [VenuePref] = []) {
        self.config = config

        var exact: [String: (tier: Int, abbr: String)] = [:]
        var substring: [(phrase: String, tier: Int, abbr: String)] = []

        for v in venues where !v.phrase.isEmpty {
            let key = v.phrase.lowercased()
            if v.exact == true {
                if let existing = exact[key] {
                    if v.tier < existing.tier {
                        exact[key] = (v.tier, v.abbr)
                    }
                } else {
                    exact[key] = (v.tier, v.abbr)
                }
            } else {
                substring.append((key, v.tier, v.abbr))
            }
        }

        substring.sort { $0.phrase.count > $1.phrase.count }

        self.exactMatches = exact
        self.substringMatches = substring
    }

    private func matchVenue(_ venueLower: String) -> (tier: Int, abbr: String)? {
        if let match = exactMatches[venueLower] {
            return (match.tier, match.abbr)
        }

        var best: (tier: Int, abbr: String, len: Int)?
        for rule in substringMatches where venueLower.contains(rule.phrase) {
            let len = rule.phrase.count
            if best == nil || len > best!.len || (len == best!.len && rule.tier < best!.tier) {
                best = (rule.tier, rule.abbr, len)
            }
        }
        guard let best else { return nil }
        return (best.tier, best.abbr)
    }

    func evaluate(venue: String, citations: Int) -> (tier: Int, abbr: String, score: Double) {
        let citation = citationScore(citations: citations)
        guard !venue.isEmpty else { return (0, "Others", citation) }

        let venueLower = venue.lowercased()
        let match = matchVenue(venueLower)
        let abbr = match?.abbr ?? "Others"

        var tier = match?.tier ?? 0
        if tier != 0, isBlacklisted(venueLower) {
            tier = 0
        }

        var base = 0.0
        if let tierConfig = config.scoring.tiers[String(tier)] {
            base = Double(tierConfig.points)
        }
        return (tier, abbr, base + citation)
    }

    private func isBlacklisted(_ venueLower: String) -> Bool {
        guard let blacklist = config.filters?.venue_blacklist else { return false }
        return blacklist.contains { venueLower.contains($0.lowercased()) }
    }

    private func citationScore(citations: Int) -> Double {
        var remaining = Double(citations)
        var previousLimit = 0.0
        var score = 0.0

        for seg in config.scoring.citation_breakpoints {
            let rate = seg.points_per_citation
            if let upTo = seg.up_to {
                let limit = Double(upTo)
                let count = max(0.0, min(remaining, limit - previousLimit))
                score += count * rate
                remaining -= count
                previousLimit = limit
            } else {
                let count = max(0.0, remaining)
                score += count * rate
                remaining -= count
            }
            if remaining <= 0 {
                break
            }
        }

        return min(score, Double(config.scoring.max_citation_points))
    }
}
