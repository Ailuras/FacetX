import Foundation

struct RecommendationResult {
    var paper: Paper
    var reason: String
    var slotIndex: Int
}

class RecommendEngine {
    let config: AppConfig

    init(config: AppConfig) {
        self.config = config
    }

    private static let pubDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func isRecent(paper: Paper, cutoff: Date) -> Bool {
        guard let pubDate = Self.pubDateFormatter.date(from: paper.publicationDate) else { return false }
        return pubDate >= cutoff
    }

    /// Picks up to `count` new papers from the unrecommended pool and appends
    /// them to the recommendation list. Already-recommended papers are never
    /// touched — call `setPaperRecommended(id:isRecommended:false)` explicitly
    /// to remove individual picks.
    func recommend(papers: [Paper], count: Int? = nil) -> [RecommendationResult] {
        let recConfig = config.recommendation
        let dailyCount = count ?? recConfig.daily_count
        let qualitySlots = min(recConfig.quality_slots, dailyCount)
        let highThreshold = Double(recConfig.high_score_threshold)
        let recentDays = recConfig.recent_days

        if papers.isEmpty { return [] }

        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -recentDays, to: Date()) else {
            return []
        }

        // Only consider papers not already recommended; pending papers are exhausted first.
        let unrecommended = papers.filter { !$0.isRecommended }
        let pendingPool = unrecommended.filter { $0.status == .pending }
        let fallbackPool = unrecommended.filter { $0.status != .pending }

        let recentPendingPool = pendingPool.filter { isRecent(paper: $0, cutoff: cutoffDate) }
        let highPendingPool = pendingPool.filter { $0.score >= highThreshold }
        let recentFallbackPool = fallbackPool.filter { isRecent(paper: $0, cutoff: cutoffDate) }
        let highFallbackPool = fallbackPool.filter { $0.score >= highThreshold }

        var excludeIds = Set<String>()
        var selected: [RecommendationResult] = []

        func popRandom(from pool: [Paper]) -> Paper? {
            let valid = pool.filter { !excludeIds.contains($0.id) }
            guard let randomPaper = valid.randomElement() else { return nil }
            excludeIds.insert(randomPaper.id)
            return randomPaper
        }

        // 1. Quality priority slots
        for i in 0..<qualitySlots {
            var reason = "Pending Quality Pick (score >= \(Int(highThreshold)))"
            var px = popRandom(from: highPendingPool)

            if px == nil {
                px = popRandom(from: recentPendingPool)
                reason = "Pending Recent Pick (last \(recentDays)d)"
            }
            if px == nil {
                px = popRandom(from: pendingPool)
                reason = "Pending Exploration Pick"
            }
            if px == nil {
                px = popRandom(from: highFallbackPool)
                reason = "Backfill Quality Pick (score >= \(Int(highThreshold)))"
            }
            if px == nil {
                px = popRandom(from: recentFallbackPool)
                reason = "Backfill Recent Pick (last \(recentDays)d)"
            }
            if px == nil {
                px = popRandom(from: fallbackPool)
                reason = "Backfill Exploration Pick"
            }

            if let chosen = px {
                selected.append(RecommendationResult(paper: chosen, reason: reason, slotIndex: i))
            }
        }

        // 2. Recency priority slots
        for i in qualitySlots..<dailyCount {
            var reason = "Pending Recent Pick (last \(recentDays)d)"
            var px = popRandom(from: recentPendingPool)

            if px == nil {
                px = popRandom(from: pendingPool)
                reason = "Pending Exploration Pick"
            }
            if px == nil {
                px = popRandom(from: recentFallbackPool)
                reason = "Backfill Recent Pick (last \(recentDays)d)"
            }
            if px == nil {
                px = popRandom(from: fallbackPool)
                reason = "Backfill Exploration Pick"
            }

            if let chosen = px {
                selected.append(RecommendationResult(paper: chosen, reason: reason, slotIndex: i))
            }
        }

        return selected
    }
}
