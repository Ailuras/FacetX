import Foundation
import Observation

struct PaperWorkflowResult {
    var didRun: Bool
    var message: String
    var toastType: ToastType
}

@MainActor
@Observable
final class PaperWorkflowService {
    static let shared = PaperWorkflowService()

    var isFetching = false
    var isRecommending = false

    var isBusy: Bool { isFetching || isRecommending }

    private init() {}

    func fetchPapers() async -> PaperWorkflowResult {
        guard !isBusy else {
            return PaperWorkflowResult(
                didRun: false,
                message: L10n.pick("Another literature workflow is already running.",
                                   "另一个文献工作流正在运行。"),
                toastType: .info
            )
        }

        let config = ConfigManager.shared.effectiveConfig
        let configuredTracks = config.tracks.filter {
            !$0.value.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !configuredTracks.isEmpty else {
            return PaperWorkflowResult(
                didRun: false,
                message: L10n.pick("No literature topics have search queries configured.",
                                   "尚无文献主题配置了检索式。"),
                toastType: .warning
            )
        }

        isFetching = true
        defer { isFetching = false }

        do {
            let fetcher = OpenAlexFetcher(config: config, venues: MetadataStore.shared.venues)
            let result = try await fetcher.fetch()
            let stats = PaperStore.shared.addOrUpdate(papers: result.papers)
            let message = fetchStatusMessage(
                inserted: stats.inserted,
                updated: stats.updated,
                failedTracks: result.failedTracks
            )
            return PaperWorkflowResult(didRun: true, message: message, toastType: .success)
        } catch {
            return PaperWorkflowResult(
                didRun: false,
                message: L10n.pick("Fetch failed: \(error.localizedDescription)",
                                   "拉取失败：\(error.localizedDescription)"),
                toastType: .error
            )
        }
    }

    func recommendPapers() async -> PaperWorkflowResult {
        guard !isBusy else {
            return PaperWorkflowResult(
                didRun: false,
                message: L10n.pick("Another literature workflow is already running.",
                                   "另一个文献工作流正在运行。"),
                toastType: .info
            )
        }

        isRecommending = true
        defer { isRecommending = false }

        let candidates = PaperStore.shared.papers.filter { !$0.isRecommended }
        guard !candidates.isEmpty else {
            return PaperWorkflowResult(
                didRun: true,
                message: L10n.pick("No new papers to recommend.", "没有新的可推荐文献。"),
                toastType: .info
            )
        }

        let engine = RecommendEngine(config: ConfigManager.shared.effectiveConfig)
        let selected = engine.recommend(papers: candidates)
        for result in selected {
            PaperStore.shared.setPaperRecommended(
                id: result.paper.id,
                isRecommended: true,
                reason: recommendationReason(for: result.paper)
            )
        }

        let message = selected.isEmpty
            ? L10n.pick("No new papers to recommend.", "没有新的可推荐文献。")
            : L10n.pick("Recommended \(selected.count) papers.",
                        "已推荐 \(selected.count) 篇文献。")
        return PaperWorkflowResult(
            didRun: true,
            message: message,
            toastType: selected.isEmpty ? .info : .success
        )
    }

    private func fetchStatusMessage(inserted: Int, updated: Int, failedTracks: [String]) -> String {
        let base = L10n.pick(
            "Fetched papers: \(inserted) new, \(updated) updated.",
            "文献拉取完成：新增 \(inserted) 篇，更新 \(updated) 篇。"
        )
        guard !failedTracks.isEmpty else { return base }
        return base + " " + L10n.pick(
            "Failed topics: \(failedTracks.joined(separator: ", ")).",
            "失败主题：\(failedTracks.joined(separator: ", "))。"
        )
    }

    private func recommendationReason(for paper: Paper) -> String {
        let pieces = [
            paper.venueAbbr.isEmpty ? nil : paper.venueAbbr,
            paper.score > 0 ? String(format: L10n.pick("score %.1f", "评分 %.1f"), paper.score) : nil,
            paper.citedByCount > 0 ? L10n.pick("\(paper.citedByCount) citations", "被引 \(paper.citedByCount)") : nil
        ].compactMap { $0 }
        return pieces.joined(separator: " · ")
    }
}
