import Foundation

struct RecommendationResult {
    var paper: Paper
    var reason: String
    var slotIndex: Int
}

/// Picks a small daily set of papers from a topic's pool, balancing high-score
/// "quality" picks with recent-publication picks, preferring pending papers.
/// Ported from VellumX, scoped to a single topic by the caller.
struct RecommendEngine {
    let config: AppConfig

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

    func recommend(papers: [Paper], count: Int? = nil) -> [RecommendationResult] {
        let recConfig = config.recommendation
        let dailyCount = count ?? recConfig.daily_count
        let qualitySlots = min(recConfig.quality_slots, dailyCount)
        let highThreshold = Double(recConfig.high_score_threshold)
        let recentDays = recConfig.recent_days

        guard !papers.isEmpty, dailyCount > 0 else { return [] }

        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -recentDays, to: Date()) else {
            return []
        }

        let pendingPool = papers.filter { $0.status == .pending }
        let fallbackPool = papers.filter { $0.status != .pending }

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

        let qualityReason = L10n.pick("Quality pick (score ≥ \(Int(highThreshold)))", "高分推荐（评分 ≥ \(Int(highThreshold))）")
        let recentReason = L10n.pick("Recent pick (last \(recentDays)d)", "近期推荐（近 \(recentDays) 天）")
        let exploreReason = L10n.pick("Exploration pick", "探索推荐")

        // 1. Quality priority slots
        for i in 0..<qualitySlots {
            var reason = qualityReason
            var px = popRandom(from: highPendingPool)
            if px == nil { px = popRandom(from: recentPendingPool); reason = recentReason }
            if px == nil { px = popRandom(from: pendingPool); reason = exploreReason }
            if px == nil { px = popRandom(from: highFallbackPool); reason = qualityReason }
            if px == nil { px = popRandom(from: recentFallbackPool); reason = recentReason }
            if px == nil { px = popRandom(from: fallbackPool); reason = exploreReason }
            if let chosen = px {
                selected.append(RecommendationResult(paper: chosen, reason: reason, slotIndex: i))
            }
        }

        // 2. Recency priority slots
        for i in qualitySlots..<dailyCount {
            var reason = recentReason
            var px = popRandom(from: recentPendingPool)
            if px == nil { px = popRandom(from: pendingPool); reason = exploreReason }
            if px == nil { px = popRandom(from: recentFallbackPool); reason = recentReason }
            if px == nil { px = popRandom(from: fallbackPool); reason = exploreReason }
            if let chosen = px {
                selected.append(RecommendationResult(paper: chosen, reason: reason, slotIndex: i))
            }
        }

        return selected
    }
}
